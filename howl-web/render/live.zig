//! Live browser renderer: framed Howl snapshot bytes -> shared view/text/Canvas state.
const std = @import("std");
const session = @import("howl_session");
const client = @import("howl_client");
const render = @import("howl_render");
const canvas = render.canvas;
const text = render.text;
const p = session.protocol;

pub const panic = std.debug.FullPanic(trapPanic);
fn trapPanic(_: []const u8, _: ?usize) noreturn {
    @trap();
}

const command_capacity = render.presentation.maximum_canvas_commands;
const atlas_bytes = 1024 * 1024;
const maximum_terminal_images: usize = render.terminal.maximum_external_images;
const residency_capacity = maximum_terminal_images + 1;

comptime {
    if (maximum_terminal_images != 7)
        @compileError("Web terminal image bound drifted from the portable client contract");
}

var font_input: [8 * 1024 * 1024]u8 = undefined;
var fallback_font_input: [2 * 1024 * 1024]u8 = undefined;
var symbol_font_input: [3 * 1024 * 1024]u8 = undefined;
var snapshot_input: [p.maximum_observation_bytes]u8 = undefined;
var persistent_heap: [64 * 1024 * 1024]u8 = undefined;
var transient_heap: [20 * 1024 * 1024]u8 = undefined;
var metadata: [32 * 1024 * 1024]u8 = undefined;
var metadata_used: usize = 0;
var pixels: [atlas_bytes]u8 = undefined;
var pixels_used: usize = 0;
var frame_uploads: [residency_capacity]canvas.FrameResourceUpload = undefined;
var frame_removals: [residency_capacity]canvas.FrameResourceRef = undefined;
var frame_commands: [command_capacity]canvas.Command = undefined;
var accepted_residency: [residency_capacity]canvas.Residency = undefined;
var accepted_residency_count: usize = 0;
var pending_residency: [residency_capacity]canvas.Residency = undefined;
var pending_residency_count: usize = 0;
var missing_external_storage: [maximum_terminal_images]canvas.FrameExternalResource = undefined;
var missing_external: ?canvas.FrameExternalResource = null;
var image_bindings: [maximum_terminal_images]ImageBinding = undefined;
var image_binding_count: usize = 0;
var missing_image_binding: ?ImageBinding = null;
var pending_ack = false;
var failure: []const u8 = "";

var persistent = std.heap.FixedBufferAllocator.init(&persistent_heap);
var transient = std.heap.FixedBufferAllocator.init(&transient_heap);
var fonts: ?*text.FontSet = null;
var content: ?*render.terminal.Content = null;
var composer: canvas.Composer = undefined;
var composer_ready = false;
var producer: canvas.SourceId = @fromBackingInt(0);
var cell_size: canvas.Size = .{ .width = 1, .height = 1 };
var surface: canvas.Size = .{ .width = 1, .height = 1 };
var rendered: u64 = 0;

const ImageBinding = render.terminal.ExternalImageBinding;

const PendingExternal = struct {
    binding: ImageBinding,
    external: canvas.FrameExternalResource,
};

const RenderResult = enum {
    frame,
    external,
};

export fn rv_font_ptr() usize {
    return @intFromPtr(&font_input);
}
export fn rv_font_capacity() usize {
    return font_input.len;
}
export fn rv_fallback_font_ptr() usize {
    return @intFromPtr(&fallback_font_input);
}
export fn rv_fallback_font_capacity() usize {
    return fallback_font_input.len;
}
export fn rv_symbol_font_ptr() usize {
    return @intFromPtr(&symbol_font_input);
}
export fn rv_symbol_font_capacity() usize {
    return symbol_font_input.len;
}
export fn rv_snapshot_ptr() usize {
    return @intFromPtr(&snapshot_input);
}
export fn rv_snapshot_capacity() usize {
    return snapshot_input.len;
}
export fn rv_frame_ptr() usize {
    return @intFromPtr(&metadata);
}
export fn rv_frame_len() usize {
    return metadata_used;
}
export fn rv_pixels_ptr() usize {
    return @intFromPtr(&pixels);
}
export fn rv_pixels_len() usize {
    return pixels_used;
}
export fn rv_error_ptr() usize {
    return @intFromPtr(failure.ptr);
}
export fn rv_error_len() usize {
    return failure.len;
}
export fn rv_render_count() u64 {
    return rendered;
}
export fn rv_ready() u32 {
    return @intFromBool(composer_ready);
}
export fn rv_missing_external() u32 {
    return @intFromBool(missing_external != null);
}
export fn rv_missing_source() u64 {
    return if (missing_external) |value| @backingInt(value.resource.source) else 0;
}
export fn rv_missing_resource() u64 {
    return if (missing_external) |value| @backingInt(value.resource.resource) else 0;
}
export fn rv_missing_generation() u64 {
    return if (missing_external) |value| @backingInt(value.resource.generation) else 0;
}
export fn rv_missing_format() u32 {
    return if (missing_external) |value| @backingInt(value.format) else 0;
}
export fn rv_missing_width() u32 {
    return if (missing_external) |value| value.size.width else 0;
}
export fn rv_missing_height() u32 {
    return if (missing_external) |value| value.size.height else 0;
}
export fn rv_missing_stride() usize {
    return if (missing_external) |value| value.stride else 0;
}
export fn rv_missing_image_id() u32 {
    return if (missing_external != null and missing_image_binding != null)
        missing_image_binding.?.image_id
    else
        0;
}
export fn rv_missing_image_generation() u64 {
    return if (missing_external != null and missing_image_binding != null)
        missing_image_binding.?.generation
    else
        0;
}

fn fail(message: []const u8) u32 {
    failure = message;
    metadata_used = 0;
    pixels_used = 0;
    return 0;
}

export fn rv_init(font_length: usize, fallback_font_length: usize, symbol_font_length: usize, font_pixels: u32) u32 {
    if (composer_ready or font_pixels < 6 or font_pixels > 64 or font_length == 0 or font_length > font_input.len or
        fallback_font_length == 0 or fallback_font_length > fallback_font_input.len or
        symbol_font_length == 0 or symbol_font_length > symbol_font_input.len) return 0;
    persistent.reset();
    transient.reset();
    accepted_residency_count = 0;
    pending_residency_count = 0;
    missing_external = null;
    image_binding_count = 0;
    missing_image_binding = null;
    pending_ack = false;
    rendered = 0;
    failure = "";
    metadata_used = 0;
    pixels_used = 0;

    const allocator = persistent.allocator();
    const fallback_sources = [_][]const u8{
        fallback_font_input[0..fallback_font_length],
        symbol_font_input[0..symbol_font_length],
    };
    const new_fonts = text.FontSet.initMemory(allocator, .{
        .primary = font_input[0..font_length],
        .fallbacks = &fallback_sources,
        .size = .{ .pixels = @intCast(font_pixels) },
    }) catch |err| return fail(@errorName(err));
    errdefer new_fonts.deinit();
    @memset(font_input[0..font_length], 0xa5);
    @memset(fallback_font_input[0..fallback_font_length], 0x5a);
    @memset(symbol_font_input[0..symbol_font_length], 0x3c);
    const metrics = new_fonts.metrics();
    const new_content = render.terminal.initContent(allocator, new_fonts, .{
        .cell_size = .{ .width = metrics.advance_width, .height = metrics.line_height },
        .box_drawing = .{
            .dpi_x = .{ .numerator = 96, .denominator = 1 },
            .dpi_y = .{ .numerator = 96, .denominator = 1 },
        },
        .shape_cache = .{
            .entry_capacity = 4096,
            .scalar_capacity = 32768,
            .glyph_capacity = 32768,
            .max_sequence_scalars = 64,
        },
        .atlas = .{ .width = 1024, .height = 1024, .entry_capacity = 4096 },
        .shaped_capacity = 256,
        .raster_bytes = 256 * 1024,
        .command_capacity = command_capacity,
    }) catch |err| return fail(@errorName(err));
    errdefer render.terminal.deinitContent(new_content);
    var new_composer = canvas.Composer.init(allocator, .{
        .sources = 1,
        .retained_resources = residency_capacity,
        .retained_commands = command_capacity,
        .retained_pixel_bytes = atlas_bytes,
        .composition_sources = 1,
        .candidate_resources = residency_capacity,
        .candidate_commands = command_capacity,
        .candidate_pixel_bytes = atlas_bytes,
    }) catch |err| return fail(@errorName(err));
    errdefer new_composer.deinit();
    const new_producer = new_composer.registerSource() catch |err| return fail(@errorName(err));

    fonts = new_fonts;
    content = new_content;
    composer = new_composer;
    producer = new_producer;
    cell_size = .{ .width = metrics.advance_width, .height = metrics.line_height };
    composer_ready = true;
    return 1;
}

export fn rv_reset() u32 {
    if (composer_ready) {
        composer.deinit();
        render.terminal.deinitContent(content.?);
        fonts.?.deinit();
    }
    fonts = null;
    content = null;
    composer_ready = false;
    producer = @fromBackingInt(0);
    persistent.reset();
    transient.reset();
    accepted_residency_count = 0;
    pending_residency_count = 0;
    missing_external = null;
    image_binding_count = 0;
    missing_image_binding = null;
    pending_ack = false;
    metadata_used = 0;
    pixels_used = 0;
    rendered = 0;
    failure = "";
    return 1;
}

export fn rv_render(snapshot_length: usize) u32 {
    if (!composer_ready or pending_ack or snapshot_length == 0 or snapshot_length > snapshot_input.len)
        return 0;
    failure = "";
    metadata_used = 0;
    pixels_used = 0;
    missing_external = null;
    missing_image_binding = null;
    const result = renderSnapshot(snapshot_input[0..snapshot_length]) catch |err| return fail(@errorName(err));
    return switch (result) {
        .frame => 1,
        .external => 2,
    };
}

fn renderSnapshot(bytes: []const u8) !RenderResult {
    transient.reset();
    defer transient.reset();
    const allocator = transient.allocator();
    var rich = try client.rich.decodeFrames(allocator, bytes);
    defer rich.deinit();
    const view = try client.view.project(allocator, &rich);
    defer client.view.deinit(view);
    const begin = client.view.begin(view);
    const next_render = std.math.add(u64, rendered, 1) catch return error.RenderRevisionOverflow;
    const cursor = render.terminal.CursorContext{
        .pane = 1,
        .source = producer,
        .visible_set_revision = next_render,
        .lifecycle_revision = 1,
    };
    const update = try takeContentUpdate(view, cursor);
    try composer.apply(producer, update);
    surface = .{
        .width = std.math.mul(u16, begin.columns, cell_size.width) catch return error.SurfaceOverflow,
        .height = std.math.mul(u16, begin.rows, cell_size.height) catch return error.SurfaceOverflow,
    };
    try composer.setComposition(.{
        .surface = surface,
        .sources = &.{.{
            .source = producer,
            .origin = .{ .x = 0, .y = 0 },
            .clip = .{ .x = 0, .y = 0, .width = surface.width, .height = surface.height },
        }},
        .focused_source = producer,
    });
    const frame = composer.frame(accepted_residency[0..accepted_residency_count], .{
        .uploads = &frame_uploads,
        .removals = &frame_removals,
        .commands = &frame_commands,
        .pixels = &pixels,
    }) catch |err| switch (err) {
        error.MissingExternalResource => {
            try prepareMissingExternal();
            return .external;
        },
        else => return err,
    };
    pixels_used = frame.pixels.len;
    try collectPendingResidency(frame.commands);
    try writeFrame(frame, begin.revision, begin.terminal_revision, next_render);
    rendered = next_render;
    pending_ack = true;
    return .frame;
}

/// Installs the exact externally uploaded resource currently requested by
/// `rv_render`. The browser calls this only after its backend resource exists.
export fn rv_accept_external() u32 {
    if (!composer_ready or pending_ack) return 0;
    const value = missing_external orelse return 0;
    const residency = canvas.Residency{
        .resource = value.resource,
        .format = value.format,
        .size = value.size,
    };
    for (accepted_residency[0..accepted_residency_count]) |*current| {
        if (@backingInt(current.resource.source) == @backingInt(residency.resource.source) and
            @backingInt(current.resource.resource) == @backingInt(residency.resource.resource))
        {
            current.* = residency;
            missing_external = null;
            missing_image_binding = null;
            return 1;
        }
    }
    if (accepted_residency_count == accepted_residency.len) return 0;
    accepted_residency[accepted_residency_count] = residency;
    accepted_residency_count += 1;
    missing_external = null;
    missing_image_binding = null;
    return 1;
}

fn takeContentUpdate(
    view: *const client.view.Snapshot,
    cursor: render.terminal.CursorContext,
) !canvas.ProducerUpdate {
    const graphics = client.view.graphics(view);
    if (graphics.images.len > maximum_terminal_images)
        return error.UnsupportedGraphics;
    var candidate: [maximum_terminal_images]ImageBinding = undefined;
    const bindings = try prepareImageBindings(graphics.images, &candidate);
    const update = try render.terminal.takeContentUpdateWithImageBindings(
        content.?,
        view,
        cursor,
        bindings,
    );
    @memcpy(image_bindings[0..bindings.len], bindings);
    image_binding_count = bindings.len;
    return update;
}

fn prepareImageBindings(
    images: []const client.view.Image,
    output: *[maximum_terminal_images]ImageBinding,
) ![]const ImageBinding {
    if (images.len > output.len) return error.UnsupportedGraphics;
    const usage = render.terminal.contentUsage(content.?);
    var allocation_cursor = usage.resource_high_water;
    var first_new = true;
    for (images, 0..) |image, index| {
        if (image.image_id == 0 or image.generation == 0)
            return error.InvalidImageBinding;
        if (findImageBindingById(
            image_bindings[0..image_binding_count],
            image.image_id,
        )) |prior| {
            if (image.generation < prior.generation) return error.InvalidImageBinding;
            var binding = prior;
            if (image.generation > prior.generation) {
                binding.generation = image.generation;
                binding.resource.generation = @fromBackingInt(@intCast(image.generation));
            }
            output[index] = binding;
            continue;
        }

        const step: u64 = if (first_new and usage.resource_generation == 0) 2 else 1;
        allocation_cursor = std.math.add(u64, allocation_cursor, step) catch
            return error.ResourceIdentityOverflow;
        first_new = false;
        if (allocation_cursor == 0 or allocation_cursor > canvas.ResourceId.max_identity)
            return error.ResourceIdentityOverflow;
        output[index] = .{
            .image_id = image.image_id,
            .generation = image.generation,
            .resource = .{
                .resource = canvas.ResourceId.local(allocation_cursor) catch
                    return error.ResourceIdentityOverflow,
                .generation = @fromBackingInt(@intCast(image.generation)),
            },
        };
    }
    return output[0..images.len];
}

fn findImageBindingById(bindings: []const ImageBinding, image_id: u32) ?ImageBinding {
    for (bindings) |binding| if (binding.image_id == image_id) return binding;
    return null;
}

fn findImageBindingByResource(
    bindings: []const ImageBinding,
    resource: canvas.FrameResourceRef,
) ?ImageBinding {
    for (bindings) |binding| {
        if (binding.resource.resource == resource.resource and
            binding.resource.generation == resource.generation)
            return binding;
    }
    return null;
}

fn selectMissingExternal(missing: []const canvas.FrameExternalResource) !PendingExternal {
    if (missing.len == 0 or missing.len > image_binding_count)
        return error.InvalidExternalResource;
    var selected: ?PendingExternal = null;
    for (missing, 0..) |value, index| {
        if (@backingInt(value.resource.source) != @backingInt(producer) or
            value.format != .rgba8)
            return error.InvalidExternalResource;
        const binding = findImageBindingByResource(
            image_bindings[0..image_binding_count],
            value.resource,
        ) orelse return error.InvalidExternalResource;
        if (index == 0) selected = .{ .binding = binding, .external = value };
    }
    return selected orelse error.InvalidExternalResource;
}

fn prepareMissingExternal() !void {
    const missing = try composer.missingExternalResources(
        accepted_residency[0..accepted_residency_count],
        &missing_external_storage,
    );
    const selected = try selectMissingExternal(missing);
    missing_external = selected.external;
    missing_image_binding = selected.binding;
}

export fn rv_ack() u32 {
    if (!composer_ready or !pending_ack) return 0;
    @memcpy(accepted_residency[0..pending_residency_count], pending_residency[0..pending_residency_count]);
    accepted_residency_count = pending_residency_count;
    pending_residency_count = 0;
    pending_ack = false;
    return 1;
}

fn exactResourceEqual(a: canvas.FrameResourceRef, b: canvas.FrameResourceRef) bool {
    return @backingInt(a.source) == @backingInt(b.source) and
        @backingInt(a.resource) == @backingInt(b.resource) and
        @backingInt(a.generation) == @backingInt(b.generation);
}

fn collectPendingResidency(commands: []const canvas.Command) error{ResidencyLimit}!void {
    pending_residency_count = 0;
    for (commands) |command| {
        const view: ?canvas.FrameResourceView = switch (command) {
            .solid => null,
            .alpha_mask => |value| value.resource,
            .rgba => |value| value.resource,
        };
        const resource = view orelse continue;
        var seen = false;
        for (pending_residency[0..pending_residency_count]) |entry| {
            if (exactResourceEqual(entry.resource, resource.resource)) {
                seen = true;
                break;
            }
        }
        if (seen) continue;
        if (pending_residency_count == pending_residency.len) return error.ResidencyLimit;
        pending_residency[pending_residency_count] = .{
            .resource = resource.resource,
            .format = resource.format,
            .size = resource.size,
        };
        pending_residency_count += 1;
    }
}

fn writeFrame(frame: canvas.Composer.Frame, observation_revision: u64, terminal_revision: u64, render_revision: u64) !void {
    var writer = std.Io.Writer.fixed(&metadata);
    try writer.print(
        "{{\"schema\":\"howl.web-frame/v1\",\"render\":{d},\"observation\":{d},\"terminal\":{d},\"surface\":[{d},{d}],\"cell\":[{d},{d}],\"uploads\":[",
        .{ render_revision, observation_revision, terminal_revision, surface.width, surface.height, cell_size.width, cell_size.height },
    );
    for (frame.uploads, 0..) |upload, index| {
        if (index != 0) try writer.writeByte(',');
        try writer.print(
            "{{\"q\":[{d},{d},{d}],\"f\":{d},\"z\":[{d},{d}],\"o\":{d},\"n\":{d},\"stride\":{d}}}",
            .{
                @backingInt(upload.resource.source), @backingInt(upload.resource.resource), @backingInt(upload.resource.generation),
                @backingInt(upload.format),          upload.size.width,                     upload.size.height,
                upload.pixel_offset,                 upload.pixel_count,                    upload.stride,
            },
        );
    }
    try writer.writeAll("],\"removals\":[");
    for (frame.removals, 0..) |removal, index| {
        if (index != 0) try writer.writeByte(',');
        try writeQualified(&writer, removal);
    }
    try writer.writeAll("],\"commands\":[");
    for (frame.commands, 0..) |command, index| {
        if (index != 0) try writer.writeByte(',');
        switch (command) {
            .solid => |value| {
                try writer.writeAll("{\"k\":0,\"r\":");
                try writeRect(&writer, value.rect);
                try writer.writeAll(",\"color\":");
                try writeColor(&writer, value.color);
                try writer.writeByte('}');
            },
            .alpha_mask => |value| {
                try writer.writeAll("{\"k\":1,\"d\":");
                try writeRect(&writer, value.destination);
                try writer.writeAll(",\"c\":");
                try writeRect(&writer, value.clip);
                try writer.writeAll(",\"q\":");
                try writeQualified(&writer, value.resource.resource);
                try writer.print(",\"f\":{d},\"z\":[{d},{d}],\"s\":", .{
                    @backingInt(value.resource.format), value.resource.size.width, value.resource.size.height,
                });
                try writeSourceRect(&writer, value.resource.source, value.resource.size);
                try writer.writeAll(",\"color\":");
                try writeColor(&writer, value.color);
                try writer.print(",\"cc\":{s}}}", .{if (value.cursor_component) "true" else "false"});
            },
            .rgba => |value| {
                try writer.writeAll("{\"k\":2,\"d\":");
                try writeRect(&writer, value.destination);
                try writer.writeAll(",\"c\":");
                try writeRect(&writer, value.clip);
                try writer.writeAll(",\"q\":");
                try writeQualified(&writer, value.resource.resource);
                try writer.print(",\"f\":{d},\"z\":[{d},{d}],\"s\":", .{
                    @backingInt(value.resource.format), value.resource.size.width, value.resource.size.height,
                });
                try writeSourceRect(&writer, value.resource.source, value.resource.size);
                try writer.writeByte('}');
            },
        }
    }
    try writer.print("] ,\"pixels\":{d},\"residency\":{d}}}", .{ frame.pixels.len, accepted_residency_count });
    metadata_used = writer.end;
}

fn writeQualified(writer: *std.Io.Writer, value: canvas.FrameResourceRef) !void {
    try writer.print("[{d},{d},{d}]", .{
        @backingInt(value.source), @backingInt(value.resource), @backingInt(value.generation),
    });
}

fn writeRect(writer: *std.Io.Writer, value: canvas.Rect) !void {
    try writer.print("[{d},{d},{d},{d}]", .{ value.x, value.y, value.width, value.height });
}

fn writeColor(writer: *std.Io.Writer, value: canvas.Color) !void {
    try writer.print("[{d},{d},{d},{d}]", .{ value.r, value.g, value.b, value.a });
}

fn writeSourceRect(writer: *std.Io.Writer, value: ?canvas.SourceRect, size: canvas.Size) !void {
    const source = value orelse canvas.SourceRect{ .x = 0, .y = 0, .width = size.width, .height = size.height };
    try writer.print("[{d},{d},{d},{d}]", .{ source.x, source.y, source.width, source.height });
}
