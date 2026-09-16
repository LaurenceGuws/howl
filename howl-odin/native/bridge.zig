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

pub const SearchMatchInfo = extern struct {
    cut_revision: u64 = 0,
    row: i32 = 0,
    start_column: u16 = 0,
    end_column: u16 = 0,
    columns: u16 = 0,
    found: u8 = 0,
    complete: u8 = 1,
    alternate_screen: u8 = 0,
    _reserved: u8 = 0,
    scanned_snapshots: u32 = 0,
};

pub const SelectionRangeInfo = extern struct {
    start_row: i32 = 0,
    end_row: i32 = 0,
    start_column: u16 = 0,
    end_column: u16 = 0,
    columns: u16 = 0,
    found: u8 = 0,
    alternate_screen: u8 = 0,
    _reserved: [2]u8 = @splat(0),
};

pub const InteractionStateInfo = extern struct {
    terminal_revision: u64 = 0,
    flags: u32 = 0,
    mouse_tracking: u8 = 0,
    mouse_protocol: u8 = 0,
    pointer_mode: u8 = 0,
    _reserved: u8 = 0,
};

const interaction_info_flags = struct {
    const alternate_scroll: u32 = 1 << 0;
    const focus_reporting: u32 = 1 << 1;
};

const maximum_search_query_bytes: usize = 4096;
const maximum_search_retries: usize = 8;

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
    history_offset: u32 = 0,
    history_count: u32 = 0,
    history_row_base: u32 = 0,
    alternate_screen: bool = false,
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

pub export fn howl_odin_bridge_render_observe(raw: ?*RenderHandle, history_offset: u32) i32 {
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    renderer.clearError();
    var rich = client.rich.request(
        &renderer.connection,
        renderer.allocator,
        0,
        history_offset,
    ) catch |failure| {
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
    renderer.history_offset = begin.history_offset;
    renderer.history_count = begin.history_count;
    renderer.history_row_base = begin.history_row_base;
    renderer.alternate_screen = begin.alternate_screen;
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

pub export fn howl_odin_bridge_render_history_offset(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.history_offset;
}

pub export fn howl_odin_bridge_render_history_count(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.history_count;
}

pub export fn howl_odin_bridge_render_history_row_base(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.history_row_base;
}

pub export fn howl_odin_bridge_render_alternate_screen(raw: ?*RenderHandle) u8 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return @intFromBool(renderer.alternate_screen);
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

pub export fn howl_odin_bridge_search_match_info_size() u32 {
    return @sizeOf(SearchMatchInfo);
}

pub export fn howl_odin_bridge_selection_range_info_size() u32 {
    return @sizeOf(SelectionRangeInfo);
}

pub export fn howl_odin_bridge_interaction_state_info_size() u32 {
    return @sizeOf(InteractionStateInfo);
}

const Handle = opaque {};
const CancellationHandle = opaque {};
const OwnedSessionHandle = opaque {};

const OwnedSession = struct {
    allocator: std.mem.Allocator,
    threaded: std.Io.Threaded,
    process: ?session_process.SessionProcess = null,
};

fn currentProcessEnviron() std.process.Environ {
    const c_environ = std.c.environ;
    var count: usize = 0;
    while (c_environ[count] != null) : (count += 1) {}
    const block: std.process.Environ.Block = .{
        .slice = c_environ[0..count :null],
    };
    return .{ .block = block };
}

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
    return 5;
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
        .threaded = std.Io.Threaded.init(std.heap.page_allocator, .{
            .environ = currentProcessEnviron(),
        }),
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

pub export fn howl_odin_bridge_search_find(
    raw: ?*Handle,
    query_ptr: [*]const u8,
    query_len: usize,
    reverse_value: u8,
    origin_present: u8,
    origin_row: i32,
    origin_column: u16,
    output: *SearchMatchInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (query_len == 0 or query_len > maximum_search_query_bytes or
        reverse_value > 1 or origin_present > 1)
    {
        bridge.setError("search", "invalid_arguments");
        return 2;
    }
    const query = query_ptr[0..query_len];
    if (!std.unicode.utf8ValidateSlice(query)) {
        bridge.setError("search", "invalid_utf8");
        return 2;
    }
    const reverse = reverse_value != 0;

    var initial_rich = client.rich.request(
        &bridge.connection,
        bridge.allocator,
        0,
        0,
    ) catch |failure| {
        bridge.setError("search_observe", @errorName(failure));
        return 3;
    };
    defer initial_rich.deinit();
    const initial = client.view.project(bridge.allocator, &initial_rich) catch |failure| {
        bridge.setError("search_project", @errorName(failure));
        return 3;
    };
    defer client.view.deinit(initial);
    const initial_begin = client.view.begin(initial).*;
    output.cut_revision = initial_begin.revision;
    output.columns = initial_begin.columns;
    output.alternate_screen = @intFromBool(initial_begin.alternate_screen);
    output.complete = 1;
    output.scanned_snapshots = 1;
    if (initial_begin.rows == 0 or initial_begin.columns == 0) return 0;
    if (origin_present != 0 and origin_column >= initial_begin.columns) {
        bridge.setError("search", "origin_context_changed");
        return 4;
    }

    const cut_first: i64 = if (initial_begin.alternate_screen)
        0
    else
        initial_begin.history_row_base;
    const cut_last_u64: u64 = if (initial_begin.alternate_screen)
        initial_begin.rows - 1
    else
        @as(u64, initial_begin.history_row_base) + initial_begin.history_count + initial_begin.rows - 1;
    if (cut_last_u64 > std.math.maxInt(i32)) {
        bridge.setError("search", "row_identity_overflow");
        return 4;
    }
    const cut_last: i64 = @intCast(cut_last_u64);

    var start_row: i64 = if (origin_present != 0) origin_row else if (reverse) cut_last else cut_first;
    var start_column: u16 = if (origin_present != 0) origin_column else if (reverse) initial_begin.columns - 1 else 0;
    if (origin_present != 0) {
        if (reverse) {
            if (start_column == 0) {
                start_row -= 1;
                start_column = initial_begin.columns - 1;
            } else {
                start_column -= 1;
            }
        } else if (start_column + 1 >= initial_begin.columns) {
            start_row += 1;
            start_column = 0;
        } else {
            start_column += 1;
        }
    }
    if (start_row < cut_first) {
        if (reverse) return 0;
        start_row = cut_first;
        start_column = 0;
    }
    if (start_row > cut_last) {
        if (!reverse) return 0;
        start_row = cut_last;
        start_column = initial_begin.columns - 1;
    }

    if (initial_begin.alternate_screen) {
        return searchProjectedCut(
            bridge,
            initial,
            query,
            reverse,
            start_row,
            start_column,
            cut_first,
            cut_last,
            output,
        );
    }

    var current_row = start_row;
    var current_column = start_column;
    var metadata = initial_begin;
    var pages: usize = 0;
    const maximum_pages = @as(usize, initial_begin.history_count) / initial_begin.rows + 4;
    while (pages < maximum_pages and current_row >= cut_first and current_row <= cut_last) : (pages += 1) {
        if (metadata.columns != initial_begin.columns or metadata.alternate_screen) {
            bridge.setError("search", "context_changed");
            return 4;
        }
        const current_first: i64 = metadata.history_row_base;
        if (reverse and current_row < current_first) return 0;
        if (!reverse and current_row < current_first) {
            output.complete = 0;
            current_row = @min(cut_last, current_first + searchGuardRows(metadata.rows));
            current_column = 0;
            if (current_row > cut_last) return 0;
        }

        var retry: usize = 0;
        while (retry < maximum_search_retries) : (retry += 1) {
            const retry_first: i64 = metadata.history_row_base;
            const retry_live_top: i64 = retry_first + metadata.history_count;
            if (reverse and current_row < retry_first) return 0;
            if (!reverse and current_row < retry_first) {
                output.complete = 0;
                current_row = @min(cut_last, retry_first + searchGuardRows(metadata.rows));
                current_column = 0;
                if (current_row > cut_last) return 0;
            }
            const guard = searchGuardRows(metadata.rows);
            const desired_top = if (reverse)
                @max(retry_first, current_row - (@as(i64, metadata.rows) - 1 - guard))
            else
                @max(retry_first, current_row - guard);
            const requested_offset: u32 = if (desired_top >= retry_live_top)
                0
            else
                @intCast(@min(@as(i64, metadata.history_count), retry_live_top - desired_top));
            var page_rich = client.rich.request(
                &bridge.connection,
                bridge.allocator,
                0,
                requested_offset,
            ) catch |failure| {
                bridge.setError("search_observe", @errorName(failure));
                return 3;
            };
            defer page_rich.deinit();
            const page = client.view.project(bridge.allocator, &page_rich) catch |failure| {
                bridge.setError("search_project", @errorName(failure));
                return 3;
            };
            defer client.view.deinit(page);
            output.scanned_snapshots += 1;
            const begin = client.view.begin(page).*;
            metadata = begin;
            if (begin.columns != initial_begin.columns or begin.alternate_screen) {
                bridge.setError("search", "context_changed");
                return 4;
            }
            const actual_top: i64 = @as(i64, begin.history_row_base) + begin.history_count - begin.history_offset;
            const actual_last = actual_top + begin.rows - 1;
            if (current_row < begin.history_row_base) {
                if (reverse) return 0;
                output.complete = 0;
                current_row = @min(cut_last, @as(i64, begin.history_row_base) + searchGuardRows(begin.rows));
                current_column = 0;
                metadata = begin;
                continue;
            }
            if (current_row < actual_top or current_row > actual_last) {
                if (retry + 1 == maximum_search_retries) {
                    output.complete = 0;
                    return 0;
                }
                continue;
            }

            const search_code = searchProjectedCut(
                bridge,
                page,
                query,
                reverse,
                current_row,
                current_column,
                @max(cut_first, actual_top),
                @min(cut_last, actual_last),
                output,
            );
            if (search_code != 0) return search_code;
            if (output.found != 0) return 0;

            if (reverse) {
                current_row = @max(cut_first, actual_top) - 1;
                current_column = initial_begin.columns - 1;
            } else {
                current_row = @min(cut_last, actual_last) + 1;
                current_column = 0;
            }
            break;
        }
    }
    return 0;
}

fn searchGuardRows(rows: u16) i64 {
    if (rows <= 4) return 1;
    return @max(@as(i64, 2), @divTrunc(@as(i64, rows), 4));
}

fn searchProjectedCut(
    bridge: *Bridge,
    snapshot: *const client.view.Snapshot,
    query: []const u8,
    reverse: bool,
    start_row: i64,
    start_column: u16,
    first_row: i64,
    last_row: i64,
    output: *SearchMatchInfo,
) i32 {
    const begin = client.view.begin(snapshot);
    const top: i64 = if (begin.alternate_screen)
        0
    else
        @as(i64, begin.history_row_base) + begin.history_count - begin.history_offset;
    if (first_row > last_row or start_row < first_row or start_row > last_row) return 0;

    if (reverse) {
        var canonical_row = start_row;
        while (canonical_row >= first_row) : (canonical_row -= 1) {
            const viewport_row: u16 = @intCast(canonical_row - top);
            const bound = if (canonical_row == start_row) start_column else begin.columns - 1;
            const found = client.search.rowFrom(
                snapshot,
                bridge.allocator,
                query,
                viewport_row,
                bound,
                true,
            ) catch |failure| {
                bridge.setError("search_match", @errorName(failure));
                return 4;
            };
            if (found) |match| {
                return fillSearchMatch(match, output);
            }
        }
        return 0;
    }

    var canonical_row = start_row;
    while (canonical_row <= last_row) : (canonical_row += 1) {
        const viewport_row: u16 = @intCast(canonical_row - top);
        const bound = if (canonical_row == start_row) start_column else 0;
        const found = client.search.rowFrom(
            snapshot,
            bridge.allocator,
            query,
            viewport_row,
            bound,
            false,
        ) catch |failure| {
            bridge.setError("search_match", @errorName(failure));
            return 4;
        };
        if (found) |match| {
            return fillSearchMatch(match, output);
        }
    }
    return 0;
}

fn fillSearchMatch(match: client.search.Match, output: *SearchMatchInfo) i32 {
    const ordered = match.range.ordered();
    output.found = 1;
    output.row = ordered.start.row;
    output.start_column = match.start_column;
    output.end_column = match.end_column;
    output.columns = match.range.columns;
    output.alternate_screen = @intFromBool(match.range.alternate_screen);
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

pub export fn howl_odin_bridge_send_paste(
    raw: ?*Handle,
    bytes_ptr: [*]const u8,
    bytes_len: usize,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    client.actions.paste(&bridge.connection, bytes_ptr[0..bytes_len]) catch |failure| {
        bridge.setError("paste", @errorName(failure));
        return 2;
    };
    return 0;
}

fn selectionViewportRow(begin: *const protocol.SnapshotBegin, stable_row: i32) ?u16 {
    if (begin.rows == 0) return null;
    if (begin.alternate_screen) {
        if (stable_row < 0 or stable_row >= begin.rows) return null;
        return @intCast(stable_row);
    }
    if (begin.history_offset > begin.history_count) return null;
    const top: i64 = @as(i64, begin.history_row_base) + begin.history_count - begin.history_offset;
    const relative = @as(i64, stable_row) - top;
    if (relative < 0 or relative >= begin.rows) return null;
    return @intCast(relative);
}

/// Expands one currently displayed canonical cell into either its contiguous
/// non-space word (kind=1) or its current projected visual row (kind=2).
/// The stable target row must still be visible in the requested history window;
/// a moving-output race is rejected rather than retargeted.
pub export fn howl_odin_bridge_selection_expand(
    raw: ?*Handle,
    kind: u8,
    history_offset: u32,
    target_row: i32,
    target_column: u16,
    expected_columns: u16,
    expected_alternate_screen: u8,
    output: *SelectionRangeInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if ((kind != 1 and kind != 2) or expected_columns == 0 or expected_alternate_screen > 1) {
        bridge.setError("selection_expand", "invalid_arguments");
        return 2;
    }

    var rich = client.rich.request(
        &bridge.connection,
        bridge.allocator,
        0,
        history_offset,
    ) catch |failure| {
        bridge.setError("selection_expand_observe", @errorName(failure));
        return 3;
    };
    defer rich.deinit();
    const snapshot = client.view.project(bridge.allocator, &rich) catch |failure| {
        bridge.setError("selection_expand_project", @errorName(failure));
        return 3;
    };
    defer client.view.deinit(snapshot);

    const begin = client.view.begin(snapshot);
    const expected_alternate = expected_alternate_screen != 0;
    if (begin.columns != expected_columns or begin.alternate_screen != expected_alternate) {
        bridge.setError("selection_expand", "context_changed");
        return 4;
    }
    const viewport_row = selectionViewportRow(begin, target_row) orelse {
        bridge.setError("selection_expand", "target_moved");
        return 4;
    };
    if (target_column >= begin.columns) {
        bridge.setError("selection_expand", "target_column");
        return 4;
    }

    const maybe_range = if (kind == 1)
        client.selection.word(snapshot, viewport_row, target_column)
    else
        client.selection.visualRow(snapshot, viewport_row);
    const range = maybe_range catch |failure| {
        bridge.setError("selection_expand", @errorName(failure));
        return 4;
    } orelse return 0;
    const ordered = range.ordered();

    var end_column = ordered.end.column;
    const end_viewport_row = selectionViewportRow(begin, ordered.end.row) orelse {
        bridge.setError("selection_expand", "expanded_end_not_visible");
        return 4;
    };
    if (client.selection.visualSpan(snapshot, range, end_viewport_row)) |span| {
        end_column = span.end_column;
    }

    output.* = .{
        .start_row = ordered.start.row,
        .end_row = ordered.end.row,
        .start_column = ordered.start.column,
        .end_column = end_column,
        .columns = range.columns,
        .found = 1,
        .alternate_screen = @intFromBool(range.alternate_screen),
    };
    return 0;
}

pub export fn howl_odin_bridge_selection_extract(
    raw: ?*Handle,
    start_row: i32,
    start_column: u16,
    end_row: i32,
    end_column: u16,
    expected_columns: u16,
    expected_alternate_screen: u8,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (expected_columns == 0 or expected_alternate_screen > 1) {
        bridge.setError("selection_context", "invalid_expected_context");
        return 3;
    }
    const range = client.selection.Range{
        .anchor = .{ .row = start_row, .column = start_column },
        .focus = .{ .row = end_row, .column = end_column },
        .columns = expected_columns,
        .alternate_screen = expected_alternate_screen != 0,
    };
    const text = client.selection.extract(
        &bridge.connection,
        bridge.allocator,
        range,
    ) catch |failure| {
        bridge.setError("selection_extract", @errorName(failure));
        return 4;
    };
    defer bridge.allocator.free(text);
    if (text.len > output_capacity) {
        bridge.setError("selection_extract", "output_too_small");
        return 5;
    }
    @memcpy(output_ptr[0..text.len], text);
    output_len.* = text.len;
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

pub export fn howl_odin_bridge_interaction_state(
    raw: ?*Handle,
    output: *InteractionStateInfo,
) i32 {
    output.* = .{};
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    const state = client.state.get(&bridge.connection) catch |failure| {
        bridge.setError("interaction_state", @errorName(failure));
        return 2;
    };
    var flags: u32 = 0;
    if (state.alternate_scroll) flags |= interaction_info_flags.alternate_scroll;
    if (state.focus_reporting) flags |= interaction_info_flags.focus_reporting;
    output.* = .{
        .terminal_revision = state.terminal_revision,
        .flags = flags,
        .mouse_tracking = @intFromEnum(state.mouse_tracking),
        .mouse_protocol = @intFromEnum(state.mouse_protocol),
        .pointer_mode = state.pointer_mode,
    };
    return 0;
}

pub export fn howl_odin_bridge_send_mouse(
    raw: ?*Handle,
    kind_value: u8,
    button_value: u8,
    modifiers: u8,
    buttons_down: u8,
    row: i32,
    column: u16,
    pixels_present: u8,
    pixel_x: u32,
    pixel_y: u32,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (modifiers & ~protocol.typed_input.modifiers.known != 0 or
        pixels_present > 1)
        return 3;
    const kind = std.enums.fromInt(protocol.InputMouseKind, kind_value) orelse return 3;
    const button = std.enums.fromInt(protocol.InputMouseButton, button_value) orelse return 3;
    client.actions.mouse(&bridge.connection, .{
        .kind = kind,
        .button = button,
        .modifiers = modifiers,
        .buttons_down = buttons_down,
        .row = row,
        .column = column,
        .pixel_x = if (pixels_present != 0) pixel_x else null,
        .pixel_y = if (pixels_present != 0) pixel_y else null,
    }) catch |failure| {
        bridge.setError("mouse", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_send_focus(
    raw: ?*Handle,
    focus_value: u8,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    const focus = std.enums.fromInt(protocol.InputFocus, focus_value) orelse return 3;
    client.actions.focus(&bridge.connection, focus) catch |failure| {
        bridge.setError("focus", @errorName(failure));
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

pub export fn howl_odin_bridge_history_offset(raw: ?*Handle) u32 {
    return if (lastBegin(raw)) |begin| begin.history_offset else 0;
}

pub export fn howl_odin_bridge_history_row_base(raw: ?*Handle) u32 {
    return if (lastBegin(raw)) |begin| begin.history_row_base else 0;
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
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputKeyName.enter));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(protocol.InputKeyName.backspace));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputKeyAction.press));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(protocol.InputKeyAction.release));
    try std.testing.expectEqual(@as(u8, 1), protocol.typed_input.modifiers.shift);
    try std.testing.expectEqual(@as(u8, 4), protocol.typed_input.modifiers.control);
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(protocol.InputMouseKind.press));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(protocol.InputMouseKind.wheel));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(protocol.InputMouseButton.left));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(protocol.InputMouseButton.wheel_down));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(protocol.InputFocus.in));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(protocol.InputFocus.out));
}

test "Odin Canvas C records stay fixed and format tags follow Canvas" {
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(RenderResourceInfo));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(RenderRemovalInfo));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(RenderCommandInfo));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(canvas.ResourceFormat.alpha8));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(canvas.ResourceFormat.rgba8));
}

test "Odin search selection and interaction C records stay fixed" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(SearchMatchInfo));
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(SelectionRangeInfo));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(InteractionStateInfo));
}
