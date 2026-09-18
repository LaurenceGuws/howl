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
const terminal_render = render.terminal;
const canvas = terminal_render;

const RuntimeHandle = opaque {};
const query_declined: i32 = 6;

// One explicit desktop lifetime, constructed/destroyed by the application.
// Process and route owners borrow its I/O; no per-connection signal handlers.
const Runtime = struct {
    threaded: std.Io.Threaded,
    borrowers: std.atomic.Value(u32) = .init(0),
};

fn runtimeValue(raw: ?*RuntimeHandle) ?*Runtime {
    return if (raw) |value| @ptrCast(@alignCast(value)) else null;
}

fn retainRuntime(value: ?*Runtime) void {
    if (value) |runtime| {
        const before = runtime.borrowers.fetchAdd(1, .monotonic);
        std.debug.assert(before < 1024);
    }
}

fn releaseRuntime(value: ?*Runtime) void {
    if (value) |runtime| {
        const before = runtime.borrowers.fetchSub(1, .release);
        std.debug.assert(before > 0);
    }
}

pub export fn howl_odin_bridge_runtime_create() ?*RuntimeHandle {
    const value = std.heap.c_allocator.create(Runtime) catch return null;
    value.* = .{ .threaded = std.Io.Threaded.init(std.heap.page_allocator, .{ .environ = currentProcessEnviron() }) };
    return @ptrCast(value);
}

pub export fn howl_odin_bridge_runtime_destroy(raw: ?*RuntimeHandle) void {
    const value = runtimeValue(raw) orelse return;
    std.debug.assert(value.borrowers.load(.acquire) == 0);
    value.threaded.deinit();
    std.heap.c_allocator.destroy(value);
}

pub export fn howl_odin_bridge_interrupt_create() ?*client.Interrupt {
    return client.Interrupt.init(std.heap.c_allocator) catch null;
}

pub export fn howl_odin_bridge_interrupt_cancel(value: ?*client.Interrupt) i32 {
    const token = value orelse return 1;
    token.cancel() catch return 2;
    return 0;
}

pub export fn howl_odin_bridge_interrupt_destroy(value: ?*client.Interrupt) void {
    if (value) |token| token.deinit();
}

fn connectForHost(runtime: ?*Runtime, interrupt: ?*client.Interrupt, endpoint: []const u8, diagnostic: *client.ConnectDiagnostic) client.Error!client.Connection {
    if (runtime) |value|
        return client.Connection.connectNativeCancelable(std.heap.c_allocator, value.threaded.io(), endpoint, diagnostic, interrupt);
    // Retained socket-only diagnostic seam, not a hidden default runtime.
    return client.Connection.connectDiagnosed(std.heap.c_allocator, endpoint, diagnostic);
}

const RenderHandle = opaque {};

// Existing full-observation encoding preference, after endpoint validation.
// TCP/SSH retain compression; Unix retains its measured raw-snapshot default.
// View reuse below is independent of this heuristic and sends no extra bytes.
fn rawObservationEndpoint(endpoint: []const u8) bool {
    return std.mem.startsWith(u8, endpoint, "unix:");
}

fn requestObservation(
    connection: *client.Connection,
    allocator: std.mem.Allocator,
    after_revision: u64,
    history_offset: u32,
    raw: bool,
) client.rich.Error!client.rich.Snapshot {
    if (raw) return client.rich.requestRaw(connection, allocator, after_revision, history_offset);
    return client.rich.request(connection, allocator, after_revision, history_offset);
}

test "only validated Unix endpoints avoid same-machine text compression" {
    try std.testing.expect(rawObservationEndpoint("unix:/run/user/1000/howl.sock"));
    try std.testing.expect(!rawObservationEndpoint("/run/user/1000/howl.sock"));
    try std.testing.expect(!rawObservationEndpoint("relative.sock"));
    try std.testing.expect(!rawObservationEndpoint(""));
    try std.testing.expect(!rawObservationEndpoint("https://example.invalid"));
    try std.testing.expect(!rawObservationEndpoint("tcp://127.0.0.1:43127"));
    try std.testing.expect(!rawObservationEndpoint("tcp://192.0.2.1:43127"));
}
const render_resource_limit: usize = terminal_render.maximum_external_images + 1;
const render_atlas_extent: u16 = 512;
const render_pixel_capacity: usize = @as(usize, render_atlas_extent) * render_atlas_extent;
const render_command_capacity: usize = render.presentation.maximum_canvas_commands;
const RenderImageBinding = terminal_render.ExternalImageBinding;

const ExternalUpload = struct {
    external: canvas.FrameExternalResource,
    fetched: client.images.Resource,
};

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

const ProfileEnvInfo = extern struct {
    name_ptr: [*]const u8,
    name_len: usize,
    value_ptr: [*]const u8,
    value_len: usize,
};

const interaction_info_flags = struct {
    const alternate_scroll: u32 = 1 << 0;
    const focus_reporting: u32 = 1 << 1;
};

const maximum_search_query_bytes: usize = 4096;
const maximum_search_retries: usize = 8;

const RenderFront = struct {
    frame_revision: u64 = 0,
    begin: ?protocol.SnapshotBegin = null,
    selection_rows: [render.presentation.maximum_rows]client.selection.RowShape = undefined,
    surface: canvas.Size = .{ .width = 1, .height = 1 },
    background_rgba: u32 = 0xff211918,
};

const Render = struct {
    front: RenderFront = .{},
    allocator: std.mem.Allocator,
    runtime: ?*Runtime = null,
    connection: client.Connection,
    raw_observation: bool,
    fonts: *render.text.FontSet,
    canvas: *terminal_render.Canvas,
    cell_size: canvas.Size,
    frame_uploads: [render_resource_limit]canvas.FrameResourceUpload = undefined,
    frame_removals: [render_resource_limit]canvas.FrameResourceRef = undefined,
    frame_commands: []canvas.Command,
    frame_pixels: []u8,
    residencies: [render_resource_limit]canvas.Residency = undefined,
    residency_count: usize = 0,
    image_bindings: [terminal_render.maximum_external_images]RenderImageBinding = undefined,
    image_binding_count: usize = 0,
    missing_external: [terminal_render.maximum_external_images]canvas.FrameExternalResource = undefined,
    external_uploads: [terminal_render.maximum_external_images]ExternalUpload = undefined,
    external_upload_count: usize = 0,
    frame_upload_count: usize = 0,
    upload_count: usize = 0,
    removal_count: usize = 0,
    command_count: usize = 0,
    pixel_count: usize = 0,
    frame_revision: u64 = 0,
    // Pending snapshot facts are published only after the host accepts resources.
    begin: ?protocol.SnapshotBegin = null,
    selection_rows: [render.presentation.maximum_rows]client.selection.RowShape = undefined,
    surface: canvas.Size = .{ .width = 1, .height = 1 },
    background_rgba: u32 = 0xff211918,
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

fn renderContentConfig(cell_size: canvas.Size) terminal_render.CanvasConfig {
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
    runtime_raw: ?*RuntimeHandle,
    interrupt: ?*client.Interrupt,
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    font_ptr: [*]const u8,
    font_len: usize,
    fallback_ptr: [*]const u8,
    fallback_len: usize,
    secondary_fallback_ptr: [*]const u8,
    secondary_fallback_len: usize,
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
    const runtime = runtimeValue(runtime_raw);
    var accepted = false;
    var connect_diagnostic: client.ConnectDiagnostic = .{};
    var connection = connectForHost(
        runtime,
        interrupt,
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
    defer if (!accepted) connection.deinit();
    var fallback_storage: [2][]const u8 = undefined;
    var fallback_count: usize = 0;
    if (fallback_len != 0) {
        fallback_storage[fallback_count] = fallback_ptr[0..fallback_len];
        fallback_count += 1;
    }
    if (secondary_fallback_len != 0) {
        fallback_storage[fallback_count] = secondary_fallback_ptr[0..secondary_fallback_len];
        fallback_count += 1;
    }
    const fonts = render.text.FontSet.init(allocator, .{
        .primary = font_ptr[0..font_len],
        .fallbacks = fallback_storage[0..fallback_count],
        .size = .{ .pixels = font_pixels },
    }) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    defer if (!accepted) fonts.deinit();
    const metrics = fonts.metrics();
    const cell_size = canvas.Size{
        .width = metrics.advance_width,
        .height = metrics.line_height,
    };
    const terminal_canvas = terminal_render.initCanvas(allocator, fonts, renderContentConfig(cell_size)) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    defer if (!accepted) terminal_render.deinitCanvas(terminal_canvas);
    const frame_commands = allocator.alloc(canvas.Command, render_command_capacity) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    defer if (!accepted) allocator.free(frame_commands);
    const frame_pixels = allocator.alloc(u8, render_pixel_capacity) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    defer if (!accepted) allocator.free(frame_pixels);
    const value = allocator.create(Render) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    value.* = .{
        .allocator = allocator,
        .runtime = runtime,
        .connection = connection,
        .raw_observation = rawObservationEndpoint(endpoint_ptr[0..endpoint_len]),
        .fonts = fonts,
        .canvas = terminal_canvas,
        .cell_size = cell_size,
        .frame_commands = frame_commands,
        .frame_pixels = frame_pixels,
    };
    retainRuntime(runtime);
    accepted = true;
    return @ptrCast(value);
}

pub export fn howl_odin_bridge_render_destroy(raw: ?*RenderHandle) void {
    const value = raw orelse return;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const allocator = renderer.allocator;
    clearExternalUploads(renderer);
    allocator.free(renderer.frame_pixels);
    allocator.free(renderer.frame_commands);
    terminal_render.deinitCanvas(renderer.canvas);
    renderer.fonts.deinit();
    renderer.connection.deinit();
    releaseRuntime(renderer.runtime);
    allocator.destroy(renderer);
}

fn clearExternalUploads(renderer: *Render) void {
    var index: usize = 0;
    while (index < renderer.external_upload_count) : (index += 1) {
        renderer.external_uploads[index].fetched.deinit();
    }
    renderer.external_upload_count = 0;
}

fn findRenderImageBindingByResource(
    bindings: []const RenderImageBinding,
    resource: canvas.FrameResourceRef,
) ?RenderImageBinding {
    for (bindings) |binding| {
        if (binding.resource.resource == resource.resource and
            binding.resource.generation == resource.generation)
            return binding;
    }
    return null;
}

fn upsertResidency(
    storage: *[render_resource_limit]canvas.Residency,
    count: *usize,
    value: canvas.Residency,
) error{ResidencyLimit}!void {
    var index: usize = 0;
    while (index < count.*) : (index += 1) {
        const existing = storage[index];
        if (@backingInt(existing.resource.source) == @backingInt(value.resource.source) and
            @backingInt(existing.resource.resource) == @backingInt(value.resource.resource))
        {
            storage[index] = value;
            return;
        }
    }
    if (count.* == storage.len) return error.ResidencyLimit;
    storage[count.*] = value;
    count.* += 1;
}

fn prepareExternalUploads(
    renderer: *Render,
    bindings: []const RenderImageBinding,
    residency: *[render_resource_limit]canvas.Residency,
    residency_count: *usize,
) !void {
    const missing = try terminal_render.missingExternalResources(
        renderer.canvas,
        renderer.residencies[0..renderer.residency_count],
        &renderer.missing_external,
    );
    if (missing.len > renderer.external_uploads.len) return error.ImageLimit;
    errdefer clearExternalUploads(renderer);

    for (missing) |external| {
        if (external.resource.source != terminal_render.terminal_source or
            external.format != .rgba8)
            return error.InvalidExternalResource;
        const binding = findRenderImageBindingByResource(bindings, external.resource) orelse
            return error.InvalidImageBinding;
        var fetched = try client.images.request(
            &renderer.connection,
            renderer.allocator,
            binding.image_id,
            binding.generation,
        );
        var fetched_owned = true;
        errdefer if (fetched_owned) fetched.deinit();
        const stride = std.math.mul(usize, @as(usize, external.size.width), 4) catch
            return error.InvalidExternalResource;
        const pixel_count = std.math.mul(usize, stride, external.size.height) catch
            return error.InvalidExternalResource;
        if (fetched.width != external.size.width or fetched.height != external.size.height or
            fetched.pixels.len != pixel_count or external.stride != stride)
            return error.InvalidExternalResource;

        renderer.external_uploads[renderer.external_upload_count] = .{
            .external = external,
            .fetched = fetched,
        };
        renderer.external_upload_count += 1;
        fetched_owned = false;
        try upsertResidency(residency, residency_count, .{
            .resource = external.resource,
            .format = external.format,
            .size = external.size,
        });
    }
}

// Synchronous diagnostic entry; the desktop instead prepares on its worker and
// accepts only after the GUI has successfully installed every SDL resource.
pub export fn howl_odin_bridge_render_observe(raw: ?*RenderHandle, history_offset: u32) i32 {
    const result = howl_odin_bridge_render_prepare(raw, history_offset);
    if (result == 0) howl_odin_bridge_render_accept(raw);
    return result;
}

pub export fn howl_odin_bridge_render_accept(raw: ?*RenderHandle) void {
    const value = raw orelse return;
    const renderer: *Render = @ptrCast(@alignCast(value));
    renderer.front.frame_revision = renderer.frame_revision;
    renderer.front.begin = renderer.begin;
    renderer.front.surface = renderer.surface;
    renderer.front.background_rgba = renderer.background_rgba;
    if (renderer.begin) |begin|
        @memcpy(renderer.front.selection_rows[0..begin.rows], renderer.selection_rows[0..begin.rows]);
}

pub export fn howl_odin_bridge_render_prepare(raw: ?*RenderHandle, history_offset: u32) i32 {
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    renderer.clearError();
    clearExternalUploads(renderer);
    var rich = requestObservation(
        &renderer.connection,
        renderer.allocator,
        0,
        history_offset,
        renderer.raw_observation,
    ) catch |failure| {
        renderer.setError("observe", @errorName(failure));
        return 2;
    };
    defer rich.deinit();
    const view = client.view.project(renderer.allocator, &rich) catch |failure| {
        renderer.setError("project", @errorName(failure));
        return 3;
    };
    defer client.view.deinit(view);
    return prepareProjectedView(renderer, view);
}

// The offered immutable view is borrowed only during this call. A stale offer
// cannot roll back a renderer that observed farther ahead on its image channel.
// Code 9 means this offer is ineligible, not a transport or terminal failure.
pub export fn howl_odin_bridge_render_prepare_view(raw: ?*RenderHandle, view: ?*const client.view.Snapshot) i32 {
    const value = raw orelse return 1;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const snapshot = view orelse return 9;
    const pending_revision = if (renderer.begin) |begin| begin.revision else 0;
    if (!standaloneLiveView(snapshot) or client.view.begin(snapshot).revision < pending_revision) return 9;
    renderer.clearError();
    clearExternalUploads(renderer);
    return prepareProjectedView(renderer, snapshot);
}

fn prepareProjectedView(renderer: *Render, view: *const client.view.Snapshot) i32 {
    const begin = client.view.begin(view).*;
    if (begin.rows > renderer.selection_rows.len) {
        renderer.setError("selection_rows", "row_limit");
        return 3;
    }
    const surface = renderSurface(begin.rows, begin.columns, renderer.cell_size) catch |failure| {
        renderer.setError("surface", @errorName(failure));
        return 3;
    };
    const graphics = client.view.graphics(view);
    var candidate_bindings: [terminal_render.maximum_external_images]RenderImageBinding = undefined;
    const bindings = terminal_render.planExternalImageBindings(
        renderer.image_bindings[0..renderer.image_binding_count],
        terminal_render.canvasUsage(renderer.canvas),
        graphics.images,
        &candidate_bindings,
    ) catch |failure| {
        renderer.setError("image_bindings", @errorName(failure));
        return 3;
    };
    terminal_render.updateWithImageBindings(renderer.canvas, view, bindings) catch |failure| {
        renderer.setError("terminal_canvas", @errorName(failure));
        return 3;
    };
    @memcpy(renderer.image_bindings[0..bindings.len], bindings);
    renderer.image_binding_count = bindings.len;
    var prospective_residencies: [render_resource_limit]canvas.Residency = undefined;
    @memcpy(
        prospective_residencies[0..renderer.residency_count],
        renderer.residencies[0..renderer.residency_count],
    );
    var prospective_residency_count = renderer.residency_count;
    prepareExternalUploads(
        renderer,
        bindings,
        &prospective_residencies,
        &prospective_residency_count,
    ) catch |failure| {
        renderer.setError("image_refill", @errorName(failure));
        return 3;
    };
    const frame = terminal_render.frame(
        renderer.canvas,
        prospective_residencies[0..prospective_residency_count],
        .{
            .uploads = &renderer.frame_uploads,
            .removals = &renderer.frame_removals,
            .commands = renderer.frame_commands,
            .pixels = renderer.frame_pixels,
        },
    ) catch |failure| {
        renderer.setError("frame", @errorName(failure));
        clearExternalUploads(renderer);
        return 3;
    };
    renderer.frame_upload_count = frame.uploads.len;
    renderer.upload_count = frame.uploads.len + renderer.external_upload_count;
    renderer.removal_count = frame.removals.len;
    renderer.command_count = frame.commands.len;
    renderer.pixel_count = frame.pixels.len;
    renderer.frame_revision = frame.revision;
    renderer.background_rgba = paddingBackground(client.view.presentation(view));
    for (0..begin.rows) |row| {
        renderer.selection_rows[row] = client.selection.rowShape(view, @intCast(row)).?;
    }
    renderer.begin = begin;
    renderer.surface = surface;
    updateRenderResidency(renderer, frame.uploads, frame.removals);
    for (renderer.external_uploads[0..renderer.external_upload_count]) |external| {
        upsertResidency(&renderer.residencies, &renderer.residency_count, .{
            .resource = external.external.resource,
            .format = external.external.format,
            .size = external.external.size,
        }) catch unreachable;
    }
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

// Padding follows the same accepted presentation cut, never an inferred cell
// color or a host theme. Reverse-screen applies to the default outside-cell fill.
fn paddingBackground(presentation: *const client.rich.Presentation) u32 {
    const color = if (presentation.reverse_screen) presentation.foreground else presentation.background;
    return @as(u32, color.r) | (@as(u32, color.g) << 8) | (@as(u32, color.b) << 16) | (@as(u32, color.a) << 24);
}

pub export fn howl_odin_bridge_render_background_rgba(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0xff211918;
    const renderer: *const Render = @ptrCast(@alignCast(value));
    return renderer.front.background_rgba;
}

pub export fn howl_odin_bridge_render_surface_width(raw: ?*RenderHandle) u16 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.front.surface.width;
}

pub export fn howl_odin_bridge_render_surface_height(raw: ?*RenderHandle) u16 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    return renderer.front.surface.height;
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
    return renderer.front.frame_revision;
}

pub export fn howl_odin_bridge_render_session_revision(raw: ?*RenderHandle) u64 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    return begin.revision;
}

pub export fn howl_odin_bridge_render_history_offset(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    return begin.history_offset;
}

pub export fn howl_odin_bridge_render_history_count(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    return begin.history_count;
}

pub export fn howl_odin_bridge_render_history_row_base(raw: ?*RenderHandle) u32 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    return begin.history_row_base;
}

pub export fn howl_odin_bridge_render_alternate_screen(raw: ?*RenderHandle) u8 {
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    return @intFromBool(begin.alternate_screen);
}

/// Projects selection against this renderer's accepted frame only. No Session
/// request, allocation, text parsing, or endpoint mutation occurs while dragging.
pub export fn howl_odin_bridge_render_selection_span(
    raw: ?*RenderHandle,
    anchor_row: i32,
    anchor_column: u16,
    focus_row: i32,
    focus_column: u16,
    columns: u16,
    alternate_screen: u8,
    viewport_row: u16,
    first: *u16,
    last: *u16,
) u8 {
    first.* = 0;
    last.* = 0;
    const value = raw orelse return 0;
    const renderer: *Render = @ptrCast(@alignCast(value));
    const begin = renderer.front.begin orelse return 0;
    if (alternate_screen > 1 or viewport_row >= begin.rows or viewport_row >= renderer.front.selection_rows.len)
        return 0;
    const range = client.selection.Range{
        .anchor = .{ .row = anchor_row, .column = anchor_column },
        .focus = .{ .row = focus_row, .column = focus_column },
        .columns = columns,
        .alternate_screen = alternate_screen != 0,
    };
    const span = range.textSpan(&begin, viewport_row, renderer.front.selection_rows[viewport_row]) orelse return 0;
    first.* = span.start_column;
    last.* = span.end_column;
    return 1;
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
    if (index < renderer.frame_upload_count) {
        const upload = renderer.frame_uploads[index];
        fillRenderResourceRef(upload.resource, output);
        output.pixel_count = upload.pixel_count;
        output.stride = upload.stride;
        output.width = upload.size.width;
        output.height = upload.size.height;
        output.format = @backingInt(upload.format);
        return 0;
    }
    const external_index = index - renderer.frame_upload_count;
    if (external_index >= renderer.external_upload_count) return 2;
    const upload = renderer.external_uploads[external_index];
    fillRenderResourceRef(upload.external.resource, output);
    output.pixel_count = upload.fetched.pixels.len;
    output.stride = upload.external.stride;
    output.width = upload.external.size.width;
    output.height = upload.external.size.height;
    output.format = @backingInt(upload.external.format);
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
    if (index < renderer.frame_upload_count) {
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
    const external_index = index - renderer.frame_upload_count;
    if (external_index >= renderer.external_upload_count) return 2;
    const pixels = renderer.external_uploads[external_index].fetched.pixels;
    if (output_capacity < pixels.len) return 4;
    @memcpy(output_ptr[0..pixels.len], pixels);
    output_len.* = pixels.len;
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

pub export fn howl_odin_bridge_profile_env_info_size() u32 {
    return @sizeOf(ProfileEnvInfo);
}

const Handle = opaque {};
const OwnedSessionHandle = opaque {};
const ConsequenceHandle = opaque {};

pub const ConsequenceInfo = extern struct {
    terminal_revision: u64 = 0,
    authority_client_id: u64 = 0,
    generation: u64 = 0,
    payload_len: u32 = 0,
    kind: u8 = 0,
    reply_required: u8 = 0,
    _reserved: [2]u8 = @splat(0),
    metadata: [protocol.consequence_metadata_bytes]u8 = @splat(0),
};
comptime {
    if (@sizeOf(ConsequenceInfo) != protocol.payload_bytes.consequence_begin)
        @compileError("Odin consequence info must stay one fixed begin-sized record");
}

const ConsequenceBridge = struct {
    allocator: std.mem.Allocator,
    runtime: ?*Runtime = null,
    connection: client.Connection,
    last_error: [160]u8 = undefined,
    last_error_len: usize = 0,

    fn clearError(self: *ConsequenceBridge) void {
        self.last_error_len = 0;
    }

    fn setError(self: *ConsequenceBridge, stage: []const u8, failure_name: []const u8) void {
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

const OwnedSession = struct {
    allocator: std.mem.Allocator,
    runtime: *Runtime,
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
    runtime: ?*Runtime = null,
    connection: client.Connection,
    raw_observation: bool,
    last_begin: ?protocol.SnapshotBegin = null,
    // At most one self-contained live view, transferred or discarded by caller.
    reusable_view: ?*client.view.Snapshot = null,
    text_truncated: bool = false,
    display_title: [protocol.properties.maximum_field_bytes]u8 = undefined,
    display_title_len: usize = 0,
    task_progress: protocol.properties.Progress = .{},
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
    return 8;
}

/// Launches one client-owned canonical Session using the existing native
/// SessionProcess owner. The matching `howl-sessiond` must be packaged beside
/// the Odin executable. A null environment map deliberately inherits the
/// desktop client's current environment.
pub export fn howl_odin_bridge_owned_session_create(
    runtime_raw: ?*RuntimeHandle,
    runtime_dir_ptr: [*]const u8,
    runtime_dir_len: usize,
    shell_ptr: [*]const u8,
    shell_len: usize,
    command_ptr: [*]const u8,
    command_len: usize,
    cwd_ptr: [*]const u8,
    cwd_len: usize,
    env_ptr: [*]const ProfileEnvInfo,
    env_count: usize,
    rows: u16,
    columns: u16,
    identity: u32,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*OwnedSessionHandle {
    diagnostic_len.* = 0;
    const runtime = runtimeValue(runtime_raw) orelse {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "missing_host_runtime");
        return null;
    };
    var accepted = false;
    if (runtime_dir_len == 0 or shell_len == 0 or rows == 0 or columns == 0 or identity == 0 or
        env_count > 32 or command_len > 16384 or cwd_len > 4096)
    {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_session_launch");
        return null;
    }
    const shell = shell_ptr[0..shell_len];
    const command: ?[]const u8 = if (command_len == 0) null else command_ptr[0..command_len];
    const cwd: ?[]const u8 = if (cwd_len == 0) null else cwd_ptr[0..cwd_len];
    if (std.mem.indexOfScalar(u8, shell, 0) != null or
        (command != null and std.mem.indexOfScalar(u8, command.?, 0) != null) or
        (cwd != null and std.mem.indexOfScalar(u8, cwd.?, 0) != null))
    {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_session_launch_text");
        return null;
    }

    const allocator = std.heap.c_allocator;
    var environment_map = std.process.Environ.Map.init(allocator);
    var use_environment_map = false;
    defer if (use_environment_map) environment_map.deinit();
    if (env_count != 0) {
        use_environment_map = true;
        environment_map.putPosixBlock(currentProcessEnviron().block.view()) catch {
            writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "environment_copy_failed");
            return null;
        };
        var total_bytes: usize = 0;
        for (env_ptr[0..env_count]) |entry| {
            if (entry.name_len == 0 or entry.name_len > 255 or entry.value_len > 4096) {
                writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_environment_entry");
                return null;
            }
            const name = entry.name_ptr[0..entry.name_len];
            const value = entry.value_ptr[0..entry.value_len];
            if (!std.process.Environ.Map.validateKeyForPut(name) or std.mem.indexOfScalar(u8, value, 0) != null) {
                writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_environment_entry");
                return null;
            }
            total_bytes = std.math.add(usize, total_bytes, name.len + value.len) catch {
                writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "environment_limit");
                return null;
            };
            if (total_bytes > 64 * 1024) {
                writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "environment_limit");
                return null;
            }
            environment_map.put(name, value) catch {
                writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "environment_copy_failed");
                return null;
            };
        }
    }

    const owned = allocator.create(OwnedSession) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    owned.* = .{
        .allocator = allocator,
        .runtime = runtime,
    };
    defer if (!accepted) allocator.destroy(owned);
    owned.process = session_process.SessionProcess.launchSibling(
        allocator,
        runtime.threaded.io(),
        runtime_dir_ptr[0..runtime_dir_len],
        shell,
        command,
        cwd,
        if (use_environment_map) &environment_map else null,
        rows,
        columns,
        identity,
    ) catch |failure| {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure));
        return null;
    };
    retainRuntime(runtime);
    accepted = true;
    return @ptrCast(owned);
}

pub export fn howl_odin_bridge_owned_session_destroy(raw: ?*OwnedSessionHandle) void {
    const value = raw orelse return;
    const owned: *OwnedSession = @ptrCast(@alignCast(value));
    const allocator = owned.allocator;
    if (owned.process) |*process| process.deinit();
    releaseRuntime(owned.runtime);
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
    runtime_raw: ?*RuntimeHandle,
    interrupt: ?*client.Interrupt,
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
    const runtime = runtimeValue(runtime_raw);
    var accepted = false;
    var connect_diagnostic: client.ConnectDiagnostic = .{};
    var connection = connectForHost(
        runtime,
        interrupt,
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
    defer if (!accepted) connection.deinit();

    const bridge = allocator.create(Bridge) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    bridge.* = .{
        .allocator = allocator,
        .runtime = runtime,
        .connection = connection,
        .raw_observation = rawObservationEndpoint(endpoint_ptr[0..endpoint_len]),
    };
    retainRuntime(runtime);
    accepted = true;
    return @ptrCast(bridge);
}

pub export fn howl_odin_bridge_destroy(raw: ?*Handle) void {
    const value = raw orelse return;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    const allocator = bridge.allocator;
    if (bridge.reusable_view) |view| client.view.deinit(view);
    bridge.connection.deinit();
    releaseRuntime(bridge.runtime);
    allocator.destroy(bridge);
}

/// Requests a complete view and publishes compact metadata. The existing shared
/// immutable projection may be taken once for rendering when it has no external
/// image dependencies. Otherwise its observing connection's pin stays private.
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
    if (bridge.reusable_view) |view| client.view.deinit(view);
    bridge.reusable_view = null;

    var rich = requestObservation(
        &bridge.connection,
        bridge.allocator,
        after_revision,
        history_offset,
        bridge.raw_observation,
    ) catch |failure| {
        bridge.setError("observe", @errorName(failure));
        return 2;
    };
    defer rich.deinit();

    const projected = client.view.project(bridge.allocator, &rich) catch |failure| {
        bridge.setError("project", @errorName(failure));
        return 3;
    };
    if (standaloneLiveView(projected)) {
        bridge.reusable_view = projected;
    }
    defer if (bridge.reusable_view == null) client.view.deinit(projected);

    const text = client.view.writeVisibleText(projected, output_ptr[0..output_capacity]);
    bridge.last_begin = client.view.begin(projected).*;
    bridge.text_truncated = text.truncated;
    const properties = client.view.properties(projected);
    bridge.display_title_len = writeDisplayTitle(properties.title orelse "", &bridge.display_title);
    bridge.task_progress = properties.progress;
    output_len.* = text.bytes_written;
    return 0;
}

// No image bytes are fetched or eagerly cached to make a cut transferable.
// Image-bearing and historical projections retain the original render channel.
fn standaloneLiveView(view: *const client.view.Snapshot) bool {
    return client.view.begin(view).history_offset == 0 and client.view.graphics(view).images.len == 0;
}

/// Moves the existing allocation out. It owns no connection or runtime borrow,
/// survives further observation/bridge teardown, and must be destroyed once.
pub export fn howl_odin_bridge_snapshot_take_view(raw: ?*Handle) ?*client.view.Snapshot {
    const value = raw orelse return null;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    const view = bridge.reusable_view;
    bridge.reusable_view = null;
    return view;
}

pub export fn howl_odin_bridge_view_destroy(view: ?*client.view.Snapshot) void {
    if (view) |value| client.view.deinit(value);
}

// Property bytes are untrusted labels, not terminal input or process identity.
// Reject invalid UTF-8 and replace control/bidi formatting with ordinary spaces.
fn writeDisplayTitle(source: []const u8, output: []u8) usize {
    if (!std.unicode.utf8ValidateSlice(source)) return 0;
    var input: usize = 0;
    var used: usize = 0;
    while (input < source.len) {
        const width = std.unicode.utf8ByteSequenceLength(source[input]) catch unreachable;
        const codepoint = std.unicode.utf8Decode(source[input..][0..width]) catch unreachable;
        const control = codepoint < 0x20 or (codepoint >= 0x7f and codepoint <= 0x9f) or
            (codepoint >= 0x2028 and codepoint <= 0x202e) or
            (codepoint >= 0x2066 and codepoint <= 0x2069);
        const needed: usize = if (control) 1 else width;
        if (needed > output.len - used) break;
        if (control) output[used] = ' ' else @memcpy(output[used..][0..needed], source[input..][0..width]);
        used += needed;
        input += width;
    }
    return used;
}

pub export fn howl_odin_bridge_snapshot_title(raw: ?*Handle, output: [*]u8, capacity: usize) usize {
    const value = raw orelse return 0;
    const bridge: *const Bridge = @ptrCast(@alignCast(value));
    return writeDisplayTitle(bridge.display_title[0..bridge.display_title_len], output[0..capacity]);
}

pub export fn howl_odin_bridge_snapshot_progress(raw: ?*Handle) u16 {
    const value = raw orelse return 0;
    const bridge: *const Bridge = @ptrCast(@alignCast(value));
    return (@as(u16, @backingInt(bridge.task_progress.kind)) << 8) | bridge.task_progress.value;
}

test "desktop property labels never leak controls or partial UTF-8 to chrome" {
    var output: [64]u8 = undefined;
    const length = writeDisplayTitle("hi\x00\x1b\nλ\u{202e}", &output);
    try std.testing.expectEqualStrings("hi   λ ", output[0..length]);
    try std.testing.expectEqual(@as(usize, 0), writeDisplayTitle(&.{0xff}, &output));
    try std.testing.expectEqual(@as(usize, 0), writeDisplayTitle("λ", output[0..1]));
    try std.testing.expectEqual(@as(usize, 2), writeDisplayTitle("λx", output[0..2]));
    try std.testing.expectEqualStrings("λ", output[0..2]);
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

fn hyperlinkUriAt(
    snapshot: *const client.view.Snapshot,
    viewport_row: u16,
    column: u16,
) ?[]const u8 {
    const rows = client.view.rows(snapshot);
    if (viewport_row >= rows.len) return null;
    const row = rows[viewport_row];
    if (column >= row.cell_count) return null;
    const cells = client.view.cells(snapshot);
    const cell_index = std.math.add(usize, row.cell_offset, column) catch return null;
    if (cell_index >= cells.len) return null;
    const link_id = cells[cell_index].link_id;
    if (link_id == 0) return null;
    const links = client.view.hyperlinks(snapshot);
    const uris = client.view.uris(snapshot);
    for (links) |link| {
        if (link.link_id != link_id) continue;
        const end = std.math.add(usize, link.uri_offset, link.uri_len) catch return null;
        if (end > uris.len) return null;
        return uris[link.uri_offset..end];
    }
    return null;
}

/// Copies the exact OSC 8 URI attached to one currently displayed canonical
/// cell. The stable target row must still name the requested history window;
/// output length zero means the cell has no canonical hyperlink.
pub export fn howl_odin_bridge_hyperlink_copy(
    raw: ?*Handle,
    history_offset: u32,
    target_row: i32,
    target_column: u16,
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
        bridge.setError("hyperlink", "invalid_arguments");
        return 2;
    }
    var rich = client.rich.request(
        &bridge.connection,
        bridge.allocator,
        0,
        history_offset,
    ) catch |failure| {
        bridge.setError("hyperlink_observe", @errorName(failure));
        return 3;
    };
    defer rich.deinit();
    const snapshot = client.view.project(bridge.allocator, &rich) catch |failure| {
        bridge.setError("hyperlink_project", @errorName(failure));
        return 3;
    };
    defer client.view.deinit(snapshot);

    const begin = client.view.begin(snapshot);
    const expected_alternate = expected_alternate_screen != 0;
    if (begin.columns != expected_columns or begin.alternate_screen != expected_alternate) {
        bridge.setError("hyperlink", "context_changed");
        return query_declined;
    }
    const viewport_row = selectionViewportRow(begin, target_row) orelse {
        bridge.setError("hyperlink", "target_moved");
        return query_declined;
    };
    if (target_column >= begin.columns) {
        bridge.setError("hyperlink", "target_column");
        return query_declined;
    }
    const uri = hyperlinkUriAt(snapshot, viewport_row, target_column) orelse return 0;
    if (uri.len > output_capacity) {
        bridge.setError("hyperlink", "short_buffer");
        return query_declined;
    }
    @memcpy(output_ptr[0..uri.len], uri);
    output_len.* = uri.len;
    return 0;
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
        return query_declined;
    }
    const viewport_row = selectionViewportRow(begin, target_row) orelse {
        bridge.setError("selection_expand", "target_moved");
        return query_declined;
    };
    if (target_column >= begin.columns) {
        bridge.setError("selection_expand", "target_column");
        return query_declined;
    }

    const maybe_range = if (kind == 1)
        client.selection.word(snapshot, viewport_row, target_column)
    else
        client.selection.visualRow(snapshot, viewport_row);
    const range = maybe_range catch |failure| {
        bridge.setError("selection_expand", @errorName(failure));
        return query_declined;
    } orelse return 0;
    const ordered = range.ordered();

    var end_column = ordered.end.column;
    const end_viewport_row = selectionViewportRow(begin, ordered.end.row) orelse {
        bridge.setError("selection_expand", "expanded_end_not_visible");
        return query_declined;
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
        return if (failure == error.SelectionRejected) query_declined else 4;
    };
    defer bridge.allocator.free(text);
    if (text.len > output_capacity) {
        bridge.setError("selection_extract", "output_too_small");
        return query_declined;
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
        .mouse_tracking = @backingInt(state.mouse_tracking),
        .mouse_protocol = @backingInt(state.mouse_protocol),
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
    cell_width: u16,
    cell_height: u16,
    claim: u8,
) i32 {
    const value = raw orelse return 1;
    const bridge: *Bridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    if (claim > 1) return 3;
    const geometry: protocol.Resize = .{
        .rows = rows,
        .columns = columns,
        .cell_pixel_width = cell_width,
        .cell_pixel_height = cell_height,
    };
    const outcome = if (claim == 1)
        client.actions.resizeGeometry(&bridge.connection, geometry)
    else
        client.actions.resizeGeometryOwned(&bridge.connection, geometry);
    outcome catch |failure| {
        bridge.setError("resize", @errorName(failure));
        return switch (failure) {
            error.NotGeometryLeader => 7,
            error.ServerRejected => 8,
            else => 2,
        };
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

pub export fn howl_odin_bridge_stream_closed(raw: ?*Handle) u8 {
    return if (lastBegin(raw)) |begin| @intFromBool(begin.stream_closed) else 0;
}

pub export fn howl_odin_bridge_child_exited(raw: ?*Handle) u8 {
    return if (lastBegin(raw)) |begin| @intFromBool(begin.child_exited) else 0;
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
    if (diagnostic.route_message_len != 0 and rendered.len + 1 < output_capacity) {
        output_ptr[rendered.len] = ' ';
        const count = @min(output_capacity - rendered.len - 1, diagnostic.route_message_len);
        @memcpy(output_ptr[rendered.len + 1 ..][0..count], diagnostic.route_message[0..count]);
        output_len.* += 1 + count;
    }
}

test "bridge named key action values stay protocol-aligned" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputKeyName.enter));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(protocol.InputKeyName.backspace));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputKeyAction.press));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(protocol.InputKeyAction.release));
    try std.testing.expectEqual(@as(u8, 1), protocol.typed_input.modifiers.shift);
    try std.testing.expectEqual(@as(u8, 4), protocol.typed_input.modifiers.control);
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputMouseKind.press));
    try std.testing.expectEqual(@as(u8, 4), @backingInt(protocol.InputMouseKind.wheel));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputMouseButton.left));
    try std.testing.expectEqual(@as(u8, 5), @backingInt(protocol.InputMouseButton.wheel_down));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(protocol.InputFocus.in));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(protocol.InputFocus.out));
}

test "Odin Canvas C records stay fixed and format tags follow Canvas" {
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(RenderResourceInfo));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(RenderRemovalInfo));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(RenderCommandInfo));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(canvas.ResourceFormat.alpha8));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(canvas.ResourceFormat.rgba8));
}

test "Odin residency upsert replaces generations without growing the table" {
    const local = canvas.ResourceRef{
        .resource = try canvas.ResourceId.local(9),
        .generation = @fromBackingInt(1),
    };
    var storage: [render_resource_limit]canvas.Residency = undefined;
    var count: usize = 0;
    try upsertResidency(&storage, &count, .{
        .resource = try canvas.FrameResourceRef.local(local),
        .format = .rgba8,
        .size = .{ .width = 2, .height = 2 },
    });
    try std.testing.expectEqual(@as(usize, 1), count);
    var replacement = local;
    replacement.generation = @fromBackingInt(2);
    try upsertResidency(&storage, &count, .{
        .resource = try canvas.FrameResourceRef.local(replacement),
        .format = .rgba8,
        .size = .{ .width = 4, .height = 3 },
    });
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expectEqual(@as(u64, 2), @backingInt(storage[0].resource.generation));
    try std.testing.expectEqual(canvas.Size{ .width = 4, .height = 3 }, storage[0].size);
}

test "Odin search selection and interaction C records stay fixed" {
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(SearchMatchInfo));
    try std.testing.expectEqual(@as(usize, 20), @sizeOf(SelectionRangeInfo));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(InteractionStateInfo));
}

/// Opens one consequence-policy connection without claiming Session authority.
/// Callers can observe the current authority first and acquire only when policy
/// permits; this keeps independent desktop windows from stealing host policy
/// merely by attaching later.
pub export fn howl_odin_bridge_consequence_create(
    runtime_raw: ?*RuntimeHandle,
    interrupt: ?*client.Interrupt,
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*ConsequenceHandle {
    diagnostic_len.* = 0;
    if (endpoint_len == 0) {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_endpoint");
        return null;
    }
    const allocator = std.heap.c_allocator;
    const runtime = runtimeValue(runtime_raw);
    var accepted = false;
    var connect_diagnostic: client.ConnectDiagnostic = .{};
    const bridge = allocator.create(ConsequenceBridge) catch {
        writeDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "out_of_memory");
        return null;
    };
    defer if (!accepted) allocator.destroy(bridge);
    bridge.* = .{
        .allocator = allocator,
        .runtime = runtime,
        .connection = connectForHost(runtime, interrupt, endpoint_ptr[0..endpoint_len], &connect_diagnostic) catch |failure| {
            writeConnectDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, @errorName(failure), connect_diagnostic);
            return null;
        },
    };
    retainRuntime(runtime);
    accepted = true;
    return @ptrCast(bridge);
}

pub export fn howl_odin_bridge_consequence_client_id(raw: ?*ConsequenceHandle) u64 {
    const value = raw orelse return 0;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    return bridge.connection.client_id;
}

pub export fn howl_odin_bridge_consequence_acquire(raw: ?*ConsequenceHandle) i32 {
    const value = raw orelse return 1;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    client.consequences.acquire(&bridge.connection) catch |failure| {
        bridge.setError("acquire", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_consequence_destroy(raw: ?*ConsequenceHandle) void {
    const value = raw orelse return;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    const allocator = bridge.allocator;
    // Deliberately close rather than sending assign(no_client): endpoint disconnect
    // clears authority only if this exact connection still owns it.
    bridge.connection.deinit();
    releaseRuntime(bridge.runtime);
    allocator.destroy(bridge);
}

pub export fn howl_odin_bridge_consequence_info_size() u32 {
    return @sizeOf(ConsequenceInfo);
}

/// Observes one current consequence. Payload bytes are copied only up to the
/// caller's bounded scratch; `info.payload_len` always reports the complete size.
pub export fn howl_odin_bridge_consequence_observe(
    raw: ?*ConsequenceHandle,
    info: *ConsequenceInfo,
    payload_ptr: [*]u8,
    payload_capacity: usize,
    copied_len: *usize,
) i32 {
    info.* = .{};
    copied_len.* = 0;
    const value = raw orelse return 1;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    var snapshot = client.consequences.observe(&bridge.connection, bridge.allocator) catch |failure| {
        bridge.setError("observe", @errorName(failure));
        return 2;
    };
    defer snapshot.deinit();
    info.* = .{
        .terminal_revision = snapshot.begin.terminal_revision,
        .authority_client_id = snapshot.begin.authority_client_id,
        .generation = snapshot.begin.generation,
        .payload_len = snapshot.begin.payload_len,
        .kind = @backingInt(snapshot.begin.kind),
        .reply_required = @intFromBool(snapshot.begin.reply_required),
        .metadata = snapshot.begin.metadata,
    };
    const count = @min(payload_capacity, snapshot.payload.len);
    @memcpy(payload_ptr[0..count], snapshot.payload[0..count]);
    copied_len.* = count;
    return 0;
}

pub export fn howl_odin_bridge_consequence_consume(
    raw: ?*ConsequenceHandle,
    generation: u64,
) i32 {
    const value = raw orelse return 1;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    client.consequences.consume(&bridge.connection, generation) catch |failure| {
        bridge.setError("consume", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_consequence_reply(
    raw: ?*ConsequenceHandle,
    generation: u64,
    kind_raw: u8,
    body_ptr: [*]const u8,
    body_len: usize,
) i32 {
    const value = raw orelse return 1;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    bridge.clearError();
    const kind: client.consequences.ReplyKind = switch (kind_raw) {
        @backingInt(client.consequences.ReplyKind.clipboard) => .clipboard,
        @backingInt(client.consequences.ReplyKind.pointer_shape) => .pointer_shape,
        @backingInt(client.consequences.ReplyKind.color_preference) => .color_preference,
        @backingInt(client.consequences.ReplyKind.container_state) => .container_state,
        @backingInt(client.consequences.ReplyKind.container_position) => .container_position,
        @backingInt(client.consequences.ReplyKind.container_screen_cells) => .container_screen_cells,
        @backingInt(client.consequences.ReplyKind.container_icon_title) => .container_icon_title,
        @backingInt(client.consequences.ReplyKind.container_decline) => .container_decline,
        else => {
            bridge.setError("reply", "invalid_kind");
            return 2;
        },
    };
    client.consequences.reply(&bridge.connection, generation, kind, body_ptr[0..body_len]) catch |failure| {
        bridge.setError("reply", @errorName(failure));
        return 2;
    };
    return 0;
}

pub export fn howl_odin_bridge_consequence_copy_error(
    raw: ?*ConsequenceHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) void {
    output_len.* = 0;
    const value = raw orelse return;
    const bridge: *ConsequenceBridge = @ptrCast(@alignCast(value));
    const count = @min(output_capacity, bridge.last_error_len);
    @memcpy(output_ptr[0..count], bridge.last_error[0..count]);
    output_len.* = count;
}

test "pane gutter background follows accepted default color and screen reverse" {
    var presentation: client.rich.Presentation = undefined;
    presentation.reverse_screen = false;
    presentation.background = .{ .r = 17, .g = 34, .b = 51, .a = 255 };
    presentation.foreground = .{ .r = 221, .g = 204, .b = 187, .a = 255 };
    try std.testing.expectEqual(@as(u32, 0xff332211), paddingBackground(&presentation));
    presentation.reverse_screen = true;
    try std.testing.expectEqual(@as(u32, 0xffbbccdd), paddingBackground(&presentation));
}

test "render headers publish metadata and selection only on acceptance" {
    var renderer: Render = undefined;
    renderer.front = .{};
    renderer.begin = null;
    renderer.frame_revision = 17;
    renderer.surface = .{ .width = 400, .height = 200 };
    renderer.background_rgba = 0xff123456;
    renderer.external_upload_count = 0;
    // Eligible offers fail before accessing the deliberately undefined composer.
    renderer.cell_size = .{ .width = 0, .height = 0 };
    const handle: *RenderHandle = @ptrCast(&renderer);
    var first_begin = std.mem.zeroes(protocol.SnapshotBegin);
    first_begin.revision = 6;
    first_begin.history_offset = 4;
    first_begin.history_count = 100;
    first_begin.history_row_base = 2;
    first_begin.rows = 1;
    first_begin.columns = 8;
    var next_begin = first_begin;
    next_begin.revision = 8;
    next_begin.history_offset = 0;
    next_begin.history_count = 0;
    next_begin.history_row_base = 0;
    next_begin.alternate_screen = true;
    const live = try testReusableProjection(0, false);
    defer client.view.deinit(live);
    const historical = try testReusableProjection(1, false);
    defer client.view.deinit(historical);
    const image = try testReusableProjection(0, true);
    defer client.view.deinit(image);

    // null, unprepared, prepared, accepted, next prepared/rejected, next accepted
    for (0..6) |stage| {
        switch (stage) {
            2 => {
                renderer.begin = first_begin;
                renderer.selection_rows[0] = .{ .content_end_exclusive = 3, .wrapped = false };
            },
            3, 5 => howl_odin_bridge_render_accept(handle),
            4 => {
                // Missing, older, and equal pending headers all permit revision 7.
                // A surface failure must leave the accepted cut and selection intact.
                for ([_]?u64{ null, 6, 7 }) |revision| {
                    renderer.begin = if (revision) |value| blk: {
                        var begin = next_begin;
                        begin.revision = value;
                        break :blk begin;
                    } else null;
                    try std.testing.expectEqual(@as(i32, 3), howl_odin_bridge_render_prepare_view(handle, live));
                    try std.testing.expectEqualDeep(first_begin, renderer.front.begin.?);
                    try std.testing.expectEqualDeep(client.selection.RowShape{ .content_end_exclusive = 3, .wrapped = false }, renderer.front.selection_rows[0]);
                    try std.testing.expectEqualStrings("surface:InvalidSurface", renderer.last_error[0..renderer.last_error_len]);
                }
                // Invalid cuts remain rejected even at an eligible revision.
                for ([_]?*const client.view.Snapshot{ historical, image, null }) |offer| {
                    try std.testing.expectEqual(@as(i32, 9), howl_odin_bridge_render_prepare_view(handle, offer));
                    try std.testing.expectEqualDeep(first_begin, renderer.front.begin.?);
                }
                renderer.begin = next_begin;
                renderer.selection_rows[0] = .{ .content_end_exclusive = 1, .wrapped = true };
                // Revision 7 is newer than front 6 but older than pending 8.
                try std.testing.expectEqual(@as(i32, 9), howl_odin_bridge_render_prepare_view(handle, live));
                try std.testing.expectEqualDeep(first_begin, renderer.front.begin.?);
                try std.testing.expectEqualDeep(next_begin, renderer.begin.?);
            },
            else => {},
        }
        const raw = if (stage == 0) null else handle;
        const expected = if (stage < 3) std.mem.zeroes(protocol.SnapshotBegin) else if (stage == 5) next_begin else first_begin;
        try std.testing.expectEqual(expected.revision, howl_odin_bridge_render_session_revision(raw));
        try std.testing.expectEqual(expected.history_offset, howl_odin_bridge_render_history_offset(raw));
        try std.testing.expectEqual(expected.history_count, howl_odin_bridge_render_history_count(raw));
        try std.testing.expectEqual(expected.history_row_base, howl_odin_bridge_render_history_row_base(raw));
        try std.testing.expectEqual(@as(u8, @intFromBool(expected.alternate_screen)), howl_odin_bridge_render_alternate_screen(raw));
        var first: u16 = 99;
        var last: u16 = 99;
        const selected = howl_odin_bridge_render_selection_span(raw, 98, 0, 98, 7, 8, 0, 0, &first, &last);
        try std.testing.expectEqual(@as(u8, if (stage == 3 or stage == 4) 1 else 0), selected);
        try std.testing.expectEqual(@as(u16, 0), first);
        try std.testing.expectEqual(@as(u16, if (selected == 1) 2 else 0), last);
        if (stage == 5) {
            try std.testing.expectEqual(@as(u8, 1), howl_odin_bridge_render_selection_span(raw, 0, 0, 0, 7, 8, 1, 0, &first, &last));
            try std.testing.expectEqual(@as(u16, 0), first);
            try std.testing.expectEqual(@as(u16, 0), last);
        }
        if (stage >= 3) try std.testing.expectEqual(@as(u16, 400), howl_odin_bridge_render_surface_width(raw));
    }
}

test "completed selection rejection is distinct from interrupted transport" {
    try std.testing.expectEqual(@as(i32, 6), query_declined);
    try std.testing.expect(query_declined != 4);
}

// Small coherent fixture; projections own their bytes rather than borrowing the
// temporary rich model, just as in the real observer-to-render handoff.
fn testReusableProjection(history: u32, with_image: bool) !*client.view.Snapshot {
    var scalar = [_]u32{'x'};
    var cells = [_]client.rich.Cell{std.mem.zeroes(client.rich.Cell)};
    cells[0].scalars = &scalar;
    cells[0].width = 1;
    cells[0].height = 1;
    cells[0].subscale_n = 1;
    cells[0].subscale_d = 1;
    var rows = [_]client.rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells }};
    var rich = std.mem.zeroes(client.rich.View);
    rich.begin.revision = 7;
    rich.begin.terminal_revision = 5;
    rich.begin.rows = 1;
    rich.begin.columns = 1;
    rich.begin.history_count = history;
    rich.begin.history_offset = history;
    rich.rows = &rows;
    rich.properties.title = "shared title";
    var image = [_]protocol.SnapshotImage{.{ .image_id = 1, .generation = 1, .width = 1, .height = 1 }};
    var placement = [_]protocol.SnapshotImagePlacement{std.mem.zeroes(protocol.SnapshotImagePlacement)};
    if (with_image) {
        placement[0].image_id = 1;
        placement[0].generation = 1;
        placement[0].source_width = 1;
        placement[0].source_height = 1;
        placement[0].pixel_width = 1;
        placement[0].pixel_height = 1;
        rich.graphics.cell_pixel_width = 1;
        rich.graphics.cell_pixel_height = 1;
        rich.graphics.images = &image;
        rich.graphics.placements = &placement;
    }
    return client.view.projectView(std.testing.allocator, &rich);
}

test "live view transfer keeps exact immutable text and metadata without a connection" {
    const projected = try testReusableProjection(0, false);
    var bridge: Bridge = undefined;
    bridge.reusable_view = projected;
    const handle: *Handle = @ptrCast(&bridge);
    const taken = howl_odin_bridge_snapshot_take_view(handle).?;
    defer howl_odin_bridge_view_destroy(taken);
    try std.testing.expectEqual(projected, taken);
    try std.testing.expectEqual(@as(?*client.view.Snapshot, null), howl_odin_bridge_snapshot_take_view(handle));
    try std.testing.expect(standaloneLiveView(taken));
    try std.testing.expectEqual(@as(u64, 7), client.view.begin(taken).revision);
    try std.testing.expectEqualStrings("shared title", client.view.properties(taken).title.?);
    var text: [16]u8 = undefined;
    const written = client.view.writeVisibleText(taken, &text);
    try std.testing.expectEqualStrings("x", text[0..written.bytes_written]);
}

test "only self-contained live views may cross the observation connection boundary" {
    const live = try testReusableProjection(0, false);
    defer client.view.deinit(live);
    const historical = try testReusableProjection(1, false);
    defer client.view.deinit(historical);
    const image = try testReusableProjection(0, true);
    defer client.view.deinit(image);
    try std.testing.expect(standaloneLiveView(live));
    try std.testing.expect(!standaloneLiveView(historical));
    try std.testing.expect(!standaloneLiveView(image));
}
