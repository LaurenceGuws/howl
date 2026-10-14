//! Optional standalone Render owner. Existing schemas/direct roots do not import it.
const std = @import("std");
const render = @import("howl_render");
const terminal = render.terminal;
const native = @import("howl_render_native");
const vt_native = @import("howl_vt_native");
const source = vt_native.observation;
const fonts_mod = @import("native_fonts.zig");
/// Exact owned native schemas, shared with the existing projection leaf.
pub const c = native.c;
/// Retained read authority only, not source-owner retirement authority.
pub const Reader = source.Reader;
/// Canonical failures and explicit native admission/lifetime limits.
pub const Error = render.text.InitError || terminal.InitError || terminal.Error || native.Error ||
    source.ReadError || source.RetainError || fonts_mod.AdmissionError || error{ Busy, NoFrame };
/// One private canonical Renderer, fonts and permanently bound source.
// zig-audit: acknowledge opaque_type
// reason: Only bounded module operations may mutate canonical renderer state or its source/frame lifetime.
pub const Owner = opaque {};
/// Explicit reusable storage pins one parent namespace even between read leases.
// zig-audit: acknowledge opaque_type
// reason: Only capture/read/release/close may transition private immutable frame storage.
pub const Buffer = opaque {};
const available: u8 = 0;
const writing: u8 = 1;
const leased: u8 = 2;
const closing: u8 = 3;
const State = struct {
    allocator: std.mem.Allocator,
    reader: *Reader,
    fonts: fonts_mod.Owned,
    renderer: *terminal.Renderer,
    cell_size: terminal.Size,
    command_initial: usize,
    command_limit: usize,
    pixel_limit: usize,
    atlas_bytes: usize,
    buffer_limit: u32,
    buffer_count: u32 = 0,
    commands: []terminal.Command = &.{},
    bindings: [terminal.maximum_external_images]terminal.ExternalImageBinding = undefined,
    binding_count: usize = 0,
};
const FrameState = struct {
    allocator: std.mem.Allocator,
    parent: *State,
    phase: std.atomic.Value(u8) = .init(available),
    commands: []c.hrc_command = &.{},
    pixels: []u8 = &.{},
    uploads: [c.HRC_MAX_RESIDENCIES]c.hrc_upload = undefined,
    removals: [c.HRC_MAX_RESIDENCIES]c.hrc_removal = undefined,
    info: c.hrc_frame_info,
};
fn state(value: *Owner) *State {
    // zig-audit: acknowledge ptr_cast
    // reason: Only constructor-owned State is represented by this matching Owner.
    // zig-audit: acknowledge align_cast
    // reason: The matching allocation retains State alignment.
    return @ptrCast(@alignCast(value));
}
fn stateConst(value: *const Owner) *const State {
    // zig-audit: acknowledge ptr_cast
    // reason: A matching const Owner grants only this private State view.
    // zig-audit: acknowledge align_cast
    // reason: Const view preserves matching State allocation alignment.
    return @ptrCast(@alignCast(value));
}
fn frameState(value: *Buffer) *FrameState {
    // zig-audit: acknowledge ptr_cast
    // reason: Only module-created FrameState is represented by this matching Buffer.
    // zig-audit: acknowledge align_cast
    // reason: A matching Buffer preserves its FrameState allocation alignment.
    return @ptrCast(@alignCast(value));
}
fn frameStateConst(value: *const Buffer) *const FrameState {
    // zig-audit: acknowledge ptr_cast
    // reason: A live const Buffer grants only its private immutable lease view.
    // zig-audit: acknowledge align_cast
    // reason: The immutable view preserves matching FrameState alignment.
    return @ptrCast(@alignCast(value));
}
comptime {
    if (c.HRC_MAX_FONT_FALLBACKS != render.text.max_fallbacks or
        c.HRC_MAX_FONT_PATH_BYTES != render.text.max_font_path_bytes or
        c.HRC_MAX_FONT_BYTES != render.text.max_font_bytes or
        c.HRC_MAX_FONT_SET_BYTES != render.text.max_font_set_bytes or
        c.HRC_MAX_SHAPED != render.text.max_codepoints or
        c.HRC_MAX_SHAPED != render.text.max_glyphs or
        c.HRC_MAX_RASTER_BYTES != render.text.max_raster_bytes or
        c.HRC_MAX_ROWS != render.limits.maximum_rows or
        c.HRC_MAX_COLUMNS != render.limits.maximum_columns or
        c.HRC_MAX_FRAME_COMMANDS != render.limits.maximum_frame_commands or
        c.HRC_MAX_RESIDENCIES != terminal.maximum_external_images + 1 or
        c.HRC_MAX_FRAME_PIXEL_BYTES != vt_native.Terminal.maximum_image_storage_bytes + render.text.max_raster_bytes)
        @compileError("Review standalone Render limits against exact child owners");
}
fn item(value: usize, maximum: usize) Error!void {
    if (value > maximum) return error.ResourceLimit;
    if (value == 0) return error.InvalidArgument;
}
fn add(a: usize, b: usize) Error!usize {
    return std.math.add(usize, a, b) catch error.ResourceLimit;
}
fn multiply(a: usize, b: usize) Error!usize {
    return std.math.mul(usize, a, b) catch error.ResourceLimit;
}
fn admit(config: *const c.hrc_config) Error!terminal.Config {
    if (config.reserved != 0 or config.reserved2 != 0 or config.reserved3 != 0 or config.pixel_size == 0)
        return error.InvalidArgument;
    try item(config.shape_entries, c.HRC_MAX_CONFIG_ITEMS);
    try item(config.shape_scalars, c.HRC_MAX_CONFIG_ITEMS);
    try item(config.shape_glyphs, c.HRC_MAX_CONFIG_ITEMS);
    try item(config.atlas_entries, c.HRC_MAX_CONFIG_ITEMS);
    try item(config.max_sequence_scalars, c.HRC_MAX_SHAPED);
    try item(config.shaped_capacity, c.HRC_MAX_SHAPED);
    try item(config.raster_bytes, c.HRC_MAX_RASTER_BYTES);
    try item(config.command_capacity, c.HRC_MAX_FRAME_COMMANDS);
    try item(config.command_limit, c.HRC_MAX_FRAME_COMMANDS);
    try item(config.frame_pixel_limit, c.HRC_MAX_FRAME_PIXEL_BYTES);
    try item(config.frame_buffer_limit, c.HRC_MAX_FRAME_BUFFERS);
    if (config.max_sequence_scalars > config.shape_scalars or
        config.command_capacity > config.command_limit or config.atlas_width == 0 or config.atlas_height == 0)
        return error.InvalidArgument;
    const atlas_bytes = try multiply(config.atlas_width, config.atlas_height);
    if (atlas_bytes > c.HRC_MAX_RASTER_BYTES) return error.ResourceLimit;
    if (config.frame_pixel_limit < atlas_bytes) return error.InvalidArgument;
    const command_bytes = try multiply(config.command_limit, @sizeOf(c.hrc_command));
    const per_buffer = try add(try add(command_bytes, config.frame_pixel_limit), @sizeOf(FrameState));
    const buffers = try multiply(config.frame_buffer_limit, per_buffer);
    const scratch = try multiply(config.command_limit, @sizeOf(terminal.Command));
    // zig-audit: acknowledge discard
    // reason: Validate theoretical configured retained storage before any allocation; actual buffers grow lazily.
    _ = try add(try add(buffers, scratch), @sizeOf(State));
    const box: render.text.generated.BoxDrawingConfig = .{
        .stroke_points = config.stroke_points,
        .dpi_x = .{ .numerator = config.dpi_x_numerator, .denominator = config.dpi_x_denominator },
        .dpi_y = .{ .numerator = config.dpi_y_numerator, .denominator = config.dpi_y_denominator },
    };
    box.validate() catch return error.InvalidArgument;
    return .{
        .cell_size = .{ .width = 1, .height = 1 },
        .box_drawing = box,
        .shape_cache = .{ .entry_capacity = config.shape_entries, .scalar_capacity = config.shape_scalars, .glyph_capacity = config.shape_glyphs, .max_sequence_scalars = config.max_sequence_scalars },
        .atlas = .{ .width = config.atlas_width, .height = config.atlas_height, .gap = config.atlas_gap, .entry_capacity = config.atlas_entries },
        .shaped_capacity = config.shaped_capacity,
        .raster_bytes = config.raster_bytes,
        .command_capacity = config.command_capacity,
        .command_limit = config.command_limit,
    };
}
/// Adapts only the VT-owned Reader tag forward-declared by the Render header.
pub fn readerFromC(value: *c.struct_hvt_observation) *Reader {
    // zig-audit: acknowledge ptr_cast
    // reason: Both C declarations denote the same VT-owned opaque Reader tag; VT alone owns its allocation conversion.
    return source.fromC(@ptrCast(value));
}
/// Admits explicit fonts/budgets and permanently retains one live source Reader.
pub fn create(allocator: std.mem.Allocator, config: *const c.hrc_config, reader: *Reader) Error!*Owner {
    var core_config = try admit(config);
    const atlas_bytes = try multiply(config.atlas_width, config.atlas_height);
    // zig-audit: acknowledge discard
    // reason: Constructor validates liveness without dereferencing or retaining a canonical VT observation borrow.
    _ = try source.read(reader);
    var prepared: fonts_mod.Prepared = .{};
    try prepared.init(config);
    const retained = try source.retain(reader);
    errdefer source.release(retained);
    const value = try allocator.create(State);
    errdefer allocator.destroy(value);
    var fonts = try fonts_mod.Owned.init(allocator, &prepared);
    errdefer fonts.deinit();
    const metrics = fonts.faces().metrics();
    core_config.cell_size = .{ .width = metrics.advance_width, .height = metrics.line_height };
    const renderer = try terminal.initPrivate(allocator, fonts.faces(), core_config);
    errdefer terminal.deinit(renderer);
    value.* = .{
        .allocator = allocator,
        .reader = retained,
        .fonts = fonts,
        .renderer = renderer,
        .cell_size = core_config.cell_size,
        .command_initial = config.command_capacity,
        .command_limit = config.command_limit,
        .pixel_limit = config.frame_pixel_limit,
        .atlas_bytes = atlas_bytes,
        .buffer_limit = config.frame_buffer_limit,
    };
    // zig-audit: acknowledge ptr_cast
    // reason: Only this completely constructed matching State becomes an opaque owner.
    return @ptrCast(value);
}
/// Checked destruction ends the namespace only after all explicit buffers close.
pub fn destroy(value: *Owner) error{Busy}!void {
    const storage = state(value);
    if (storage.buffer_count != 0) return error.Busy;
    const allocator = storage.allocator;
    terminal.deinit(storage.renderer);
    allocator.free(storage.commands);
    storage.fonts.deinit();
    source.release(storage.reader);
    allocator.destroy(storage);
}
/// Copies immutable font-derived cell geometry without reading the source.
pub fn cellSize(value: *const Owner) c.hrc_cell_size {
    const size = stateConst(value).cell_size;
    return .{ .width = size.width, .height = size.height, .reserved = 0 };
}
/// Opens explicit private output storage and pins the live parent namespace.
pub fn open(value: *Owner) Error!*Buffer {
    const parent = state(value);
    if (parent.buffer_count >= parent.buffer_limit) return error.ResourceLimit;
    const frame = try parent.allocator.create(FrameState);
    frame.* = .{ .allocator = parent.allocator, .parent = parent, .info = std.mem.zeroes(c.hrc_frame_info) };
    parent.buffer_count += 1;
    // zig-audit: acknowledge ptr_cast
    // reason: Only this complete parent-bound FrameState becomes a Buffer.
    return @ptrCast(frame);
}
/// Producer closes only available storage, dropping the parent as its final access.
pub fn close(value: *Buffer) error{Busy}!void {
    const frame = frameState(value);
    if (frame.phase.cmpxchgStrong(available, closing, .acquire, .monotonic) != null) return error.Busy;
    const allocator = frame.allocator;
    const parent = frame.parent;
    allocator.free(frame.commands);
    allocator.free(frame.pixels);
    allocator.destroy(frame);
    std.debug.assert(parent.buffer_count != 0);
    parent.buffer_count -= 1;
}
/// Backend ends this lease; availability publication is its final buffer access.
pub fn release(value: *Buffer) error{NoFrame}!void {
    const frame = frameState(value);
    if (frame.phase.cmpxchgStrong(leased, available, .release, .monotonic) != null) return error.NoFrame;
}
/// Borrows only immutable copied output; never reads parent or source state.
pub fn read(value: *const Buffer) error{NoFrame}!c.hrc_frame_view {
    const frame = frameStateConst(value);
    if (frame.phase.load(.acquire) != leased) return error.NoFrame;
    return .{
        .info = frame.info,
        .commands = if (frame.info.command_count == 0) null else frame.commands.ptr,
        .uploads = if (frame.info.upload_count == 0) null else &frame.uploads,
        .removals = if (frame.info.removal_count == 0) null else &frame.removals,
    };
}
fn capacity(current: usize, needed: usize, limit: usize) Error!usize {
    if (needed > limit) return error.ResourceLimit;
    const doubled = std.math.mul(usize, current, 2) catch limit;
    return @min(limit, @max(needed, @max(doubled, 1)));
}
fn ensureCommands(parent: *State, needed: usize) Error!void {
    if (parent.commands.len >= needed) return;
    const next = try parent.allocator.alloc(terminal.Command, try capacity(parent.commands.len, needed, parent.command_limit));
    parent.allocator.free(parent.commands);
    parent.commands = next;
}
fn ensureNativeCommands(frame: *FrameState, needed: usize) Error!void {
    if (frame.commands.len >= needed) return;
    const next = try frame.allocator.alloc(c.hrc_command, try capacity(frame.commands.len, needed, frame.parent.command_limit));
    frame.allocator.free(frame.commands);
    frame.commands = next;
}
fn ensurePixels(frame: *FrameState, needed: usize, preserve: usize) Error!void {
    if (frame.pixels.len >= needed) return;
    const next = try frame.allocator.alloc(u8, try capacity(frame.pixels.len, needed, frame.parent.pixel_limit));
    std.debug.assert(preserve <= frame.pixels.len);
    @memcpy(next[0..preserve], frame.pixels[0..preserve]);
    frame.allocator.free(frame.pixels);
    frame.pixels = next;
}
fn residencies(values: []const c.hrc_residency, output: *[c.HRC_MAX_RESIDENCIES]terminal.Residency) Error![]const terminal.Residency {
    if (values.len > output.len) return error.ResourceLimit;
    for (values, 0..) |value, index| {
        if (!std.mem.allEqual(u8, &value._reserved, 0) or value.generation == 0 or value.width == 0 or value.height == 0)
            return error.InvalidArgument;
        const format: terminal.ResourceFormat = switch (value.format) {
            c.HRC_ALPHA8 => .alpha8,
            c.HRC_RGBA8 => .rgba8,
            else => return error.InvalidArgument,
        };
        output[index] = .{
            .resource = .{ .resource = terminal.ResourceId.init(value.resource) catch return error.InvalidArgument, .generation = @fromBackingInt(value.generation) },
            .format = format,
            .size = .{ .width = value.width, .height = value.height },
        };
    }
    const result = output[0..values.len];
    terminal.validateResidencies(result) catch return error.InvalidArgument;
    return result;
}
const MissingImage = struct { resource: terminal.FrameExternalResource, pixels: []const u8 };
fn imagePixels(graphics: *const vt_native.Terminal.Images, bindings: []const terminal.ExternalImageBinding, external: terminal.FrameExternalResource) Error![]const u8 {
    const binding = for (bindings) |candidate| {
        if (std.meta.eql(candidate.resource, external.resource)) break candidate;
    } else return error.InvalidImageBinding;
    const image = for (0..graphics.imageCount()) |index| {
        const candidate = graphics.image(index) orelse return error.InvalidView;
        if (candidate.id == binding.image_id and candidate.generation == binding.generation) break candidate;
    } else return error.InvalidImageBinding;
    if (external.format != .rgba8) return error.FormatMismatch;
    const stride = try multiply(external.size.width, 4);
    const bytes = try multiply(stride, external.size.height);
    if (external.stride != stride or image.width != external.size.width or image.height != external.size.height)
        return error.ExtentMismatch;
    if (image.pixels.len != bytes or bytes > vt_native.Terminal.maximum_image_bytes) return error.InvalidPixels;
    return image.pixels;
}
/// Captures complete immutable native output during one serialized source borrow.
pub fn capture(value: *Buffer, history: u32, backend: []const c.hrc_residency) Error!c.hrc_frame_info {
    var input_storage: [c.HRC_MAX_RESIDENCIES]terminal.Residency = undefined;
    const input = try residencies(backend, &input_storage);
    const frame = frameState(value);
    if (frame.phase.cmpxchgStrong(available, writing, .acquire, .monotonic) != null) return error.Busy;
    var published = false;
    defer if (!published) {
        frame.info = std.mem.zeroes(c.hrc_frame_info);
        frame.phase.store(available, .release);
    };
    const parent = frame.parent;
    const high_water = terminal.usage(parent.renderer).resource_high_water;
    for (input) |entry| {
        if (@backingInt(entry.resource.resource) > high_water) return error.InvalidArgument;
    }
    const observation = try source.read(parent.reader);
    const view = observation.semanticView(history);
    if (view.rows == 0 or view.cols == 0) return error.InvalidArgument;
    if (view.rows > c.HRC_MAX_ROWS or view.cols > c.HRC_MAX_COLUMNS) return error.ResourceLimit;
    const width = try multiply(view.cols, parent.cell_size.width);
    const height = try multiply(view.rows, parent.cell_size.height);
    if (width > std.math.maxInt(u16) or height > std.math.maxInt(u16)) return error.InvalidPresentationGeometry;
    const surface: terminal.Size = .{ .width = @intCast(width), .height = @intCast(height) };
    var planned: [terminal.maximum_external_images]terminal.ExternalImageBinding = undefined;
    const bindings = try terminal.planObservationImageBindings(parent.bindings[0..parent.binding_count], terminal.usage(parent.renderer), observation, view.history_offset, &planned);
    try terminal.updateObservation(parent.renderer, observation, view.history_offset, bindings);
    @memcpy(parent.bindings[0..bindings.len], bindings);
    parent.binding_count = bindings.len;

    var missing_storage: [terminal.maximum_external_images]terminal.FrameExternalResource = undefined;
    const missing = try terminal.missingExternalResources(parent.renderer, input, &missing_storage);
    var graphics = observation.images(view.history_offset);
    var images: [terminal.maximum_external_images]MissingImage = undefined;
    var prospective: [c.HRC_MAX_RESIDENCIES + terminal.maximum_external_images]terminal.Residency = undefined;
    @memcpy(prospective[0..input.len], input);
    var prospective_count = input.len;
    var external_bytes: usize = 0;
    for (missing, 0..) |external, index| {
        const pixels = try imagePixels(&graphics, bindings, external);
        images[index] = .{ .resource = external, .pixels = pixels };
        external_bytes = try add(external_bytes, pixels.len);
        if (external_bytes > vt_native.Terminal.maximum_image_storage_bytes) return error.ResourceLimit;
        const replacement: terminal.Residency = .{ .resource = external.resource, .format = external.format, .size = external.size };
        const prior = for (prospective[0..prospective_count], 0..) |candidate, at| {
            if (candidate.resource.resource == external.resource.resource) break at;
        } else null;
        if (prior) |at| {
            prospective[at] = replacement;
        } else {
            if (prospective_count == prospective.len) return error.ResourceLimit;
            prospective[prospective_count] = replacement;
            prospective_count += 1;
        }
    }
    try ensurePixels(frame, external_bytes, 0);
    var uploads: [c.HRC_MAX_RESIDENCIES]terminal.FrameResourceUpload = undefined;
    var removals: [c.HRC_MAX_RESIDENCIES]terminal.ResourceRef = undefined;
    var at: usize = 0;
    for (images[0..missing.len], 0..) |image, index| {
        const end = try add(at, image.pixels.len);
        @memcpy(frame.pixels[at..end], image.pixels);
        uploads[index] = .{
            .resource = image.resource.resource,
            .format = .rgba8,
            .size = image.resource.size,
            .stride = image.resource.stride,
            .pixel_offset = at,
            .pixel_count = image.pixels.len,
        };
        at = end;
    }
    try ensureCommands(parent, parent.command_initial);
    var retried_pixels = false;
    const result = while (true) {
        const candidate = terminal.frame(parent.renderer, prospective[0..prospective_count], .{
            .commands = parent.commands,
            .uploads = uploads[missing.len..],
            .removals = &removals,
            .pixels = frame.pixels[external_bytes..],
        }) catch |err| switch (err) {
            error.CommandLimit => {
                if (parent.commands.len >= parent.command_limit) return err;
                try ensureCommands(parent, try add(parent.commands.len, 1));
                continue;
            },
            error.PixelLimit => {
                if (retried_pixels) return err;
                retried_pixels = true;
                try ensurePixels(frame, try add(external_bytes, parent.atlas_bytes), external_bytes);
                continue;
            },
            else => return err,
        };
        break candidate;
    };
    const upload_count = try add(missing.len, result.uploads.len);
    for (uploads[missing.len..upload_count]) |*upload| upload.pixel_offset = try add(upload.pixel_offset, external_bytes);
    const pixel_count = try add(external_bytes, result.pixels.len);
    try ensureNativeCommands(frame, result.commands.len);
    // zig-audit: acknowledge discard
    // reason: The complete native arrays are retained privately until the final atomic lease publication.
    _ = try native.commands(result.commands, frame.commands);
    // zig-audit: acknowledge discard
    // reason: Projection returns the exact slice already described by the retained complete-frame counts.
    _ = try native.removals(result.removals, &frame.removals);
    // zig-audit: acknowledge discard
    // reason: Every pixel span is validated and all native uploads are completed before publication.
    _ = try native.uploads(uploads[0..upload_count], frame.pixels[0..pixel_count], &frame.uploads);
    const info = c.hrc_frame_info{
        .revision = result.revision,
        .content_revision = result.content_revision,
        .terminal_revision = observation.semanticSequence(),
        .command_count = @intCast(result.commands.len),
        .content_command_count = @intCast(result.content_command_count),
        .upload_count = @intCast(upload_count),
        .removal_count = @intCast(result.removals.len),
        .history_offset = view.history_offset,
        .history_count = view.history_count,
        .history_row_base = view.history_row_base,
        .background_rgba = native.background(result.commands, surface),
        .surface_width = surface.width,
        .surface_height = surface.height,
        .cell_width = parent.cell_size.width,
        .cell_height = parent.cell_size.height,
        .alternate_screen = @intFromBool(view.is_alternate_screen),
        .reserved = @splat(0),
    };
    frame.info = info;
    published = true;
    frame.phase.store(leased, .release);
    return info;
}
