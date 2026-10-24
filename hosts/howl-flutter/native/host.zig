const std = @import("std");
const builtin = @import("builtin");
const client = @import("server_client").terminal;
const native_instance = @import("howl_instance");
const vt_native = @import("howl_vt_native");
const render_native = @import("howl_render_native");
const server_client = @import("server_client");
const server_native = @import("server_client_native");
const protocol = client.protocol;
const terminal = native_instance.render.terminal;
const transported_render = @import("server_client_render");
const text = native_instance.text;
const limits = native_instance.render.limits;

// Zig 0.17's default panic path uses std.Io.Threaded.processReplace, which
// cannot compile for iOS. The embedded client must fail closed on an invariant
// violation without importing desktop process machinery.
pub const panic = if (builtin.os.tag == .ios)
    std.debug.no_panic
else
    std.debug.FullPanic(std.debug.defaultPanic);

const host_header_bytes: usize = 68;
const global_header_bytes: usize = 16;
const frame_header_bytes: usize = 48;
const resource_record_bytes: usize = 40;
const removal_record_bytes: usize = 16;
const command_record_bytes: usize = 40;
const maximum_frame_resources: usize = terminal.maximum_frame_resources;
const image_refill_header_bytes: usize = 56;
const maximum_image_refill_bytes: usize = image_refill_header_bytes +
    protocol.graphics_v2.maximum_image_bytes;
const semantic_capacity: usize = 64 * 1024;
const title_capacity: usize = protocol.properties.maximum_field_bytes;
const selection_rows_capacity: usize = limits.maximum_rows * @sizeOf(u16);
// Reuse one bounded decode/projection arena for every observation so dense live
// frames do not churn the process-global malloc arenas. Web uses the same
// reset-per-frame ownership model around this shared rich/view pipeline.
const observation_scratch_bytes: usize = 32 * 1024 * 1024;
const atlas_base_extent: u16 = 192;
const maximum_raster_scale: u16 = 4;
const maximum_atlas_extent: u16 = atlas_base_extent * maximum_raster_scale;
const pixel_capacity: usize = @as(usize, maximum_atlas_extent) * @as(usize, maximum_atlas_extent);
// One call copies a complete frame into Flutter's fixed output packet. Reserve
// every other bounded section first, then spend the exact remainder on whole
// command records so an admitted frame is always serializable by construction.
const maximum_non_command_packet_bytes: usize = host_header_bytes + global_header_bytes +
    frame_header_bytes + maximum_frame_resources * resource_record_bytes +
    maximum_frame_resources * removal_record_bytes + pixel_capacity;
// Maintained native and Web clients share one renderer-owned geometry and
// command envelope. The private Host packet remains separately byte-bounded.
const command_capacity: usize = limits.maximum_frame_commands;
// Retain one bounded common interactive row-command window. Larger/richer
// frames use the complete terminal projection path unchanged.
const incremental_command_capacity: usize = 8 * 1024;
const render_packet_budget: usize = maximum_non_command_packet_bytes + command_capacity * command_record_bytes;
const output_minimum_bytes: usize = render_packet_budget + selection_rows_capacity + semantic_capacity + title_capacity;
const maximum_packet_bytes: usize = maximum_non_command_packet_bytes + command_capacity * command_record_bytes;
const maximum_terminal_images: usize = terminal.maximum_external_images;

comptime {
    if (render_native.c.HRC_NATIVE_VERSION != 1 or @sizeOf(render_native.CommandInfo) != 64 or
        render_native.c.HRC_SOLID != 0 or render_native.c.HRC_ALPHA_MASK != 1 or render_native.c.HRC_RGBA != 2)
        @compileError("Flutter command packing requires the reviewed Render native vocabulary");
    if (vt_native.Terminal.InputEvent != native_instance.Input)
        @compileError("Flutter native input must use the exact Instance VT module identity");
    if (maximum_non_command_packet_bytes > render_packet_budget)
        @compileError("native host fixed frame state exceeds its minimum output packet");
    if (command_capacity == 0)
        @compileError("native host output packet leaves no room for terminal-frame commands");
    if (incremental_command_capacity == 0 or incremental_command_capacity > command_capacity)
        @compileError("native host incremental command budget is invalid");
    if (maximum_packet_bytes > render_packet_budget)
        @compileError("native host frame bounds exceed its minimum output packet");
    if (render_packet_budget - maximum_packet_bytes >= command_record_bytes)
        @compileError("native host command capacity does not consume the available packet budget");
    if (output_minimum_bytes - render_packet_budget != selection_rows_capacity + semantic_capacity + title_capacity)
        @compileError("native host selection/semantic/title allowance drifted from its packet budget");
    if (terminal.maximum_frame_resources > maximum_frame_resources)
        @compileError("native image bound leaves no room for the terminal glyph atlas");
}

const HostPacketError = error{
    BufferTooSmall,
    ResourceLimit,
    MissingResource,
    InvalidFrame,
    IntegerOverflow,
    InvalidResidency,
    InvalidHost,
    ImageRefillRequired,
};

/// Complete private failure surface admitted by the Flutter FFI classifier.
/// Every constituent set is owned by an existing maintained module; adding a
/// new owner failure must update this union rather than widening to anyerror.
const ClassifiedFailure = client.Error || server_native.Error ||
    server_client.Error ||
    client.actions.Error ||
    client.images.Error ||
    client.state.Error ||
    client.selection.Error ||
    client.rich.Error ||
    client.view.Error ||
    text.InitError ||
    terminal.InitError ||
    terminal.Error ||
    std.mem.Allocator.Error ||
    HostPacketError ||
    error{ Overflow, InvalidHost };

// zig-audit: acknowledge opaque_type
// reason: HostHandle hides its backing allocation from Dart; callers must return only original live handles from the matching constructor.
const HostHandle = opaque {};
// zig-audit: acknowledge opaque_type
// reason: InterruptHandle hides its backing allocation from Dart; callers must return only original live handles from the matching constructor.
const InterruptHandle = opaque {};
// zig-audit: acknowledge opaque_type
// reason: ControlHandle hides its backing allocation from Dart; callers must return only original live handles from the matching constructor.
const ControlHandle = opaque {};
const Control = struct {
    allocator: std.mem.Allocator,
    connection: *client.Connection,
};

const HostImageBinding = terminal.ExternalImageBinding;

const PendingImage = struct {
    binding: HostImageBinding,
    external: terminal.FrameExternalResource,
};

const Host = struct {
    allocator: std.mem.Allocator,
    connection: *client.Connection,
    raw_cache: client.rich.RawCache,
    cell_size: terminal.Size,
    fonts: *text.FontSet,
    renderer: *terminal.Renderer,
    frame_uploads: [maximum_frame_resources]terminal.FrameResourceUpload = undefined,
    frame_removals: [maximum_frame_resources]terminal.ResourceRef = undefined,
    frame_commands: [command_capacity]terminal.Command = undefined,
    frame_pixels: [pixel_capacity]u8 = undefined,
    residencies: [maximum_frame_resources]terminal.Residency = undefined,
    missing_external: [maximum_terminal_images]terminal.FrameExternalResource = undefined,
    image_bindings: [maximum_terminal_images]HostImageBinding = undefined,
    image_binding_count: usize = 0,
    pending_image: ?PendingImage = null,
    live_observe_pipeline: bool = false,
    armed_live_after_revision: ?u64 = null,
    live_resync_required: bool = false,
    observation_scratch: []u8,
};

fn maintainedRasterScale(font_pixels: u16, cell_width: u16, cell_height: u16) ?u16 {
    const bases = [_]struct { font: u16, cell: u16, line: u16 }{
        .{ .font = 9, .cell = 6, .line = 12 },
        .{ .font = 12, .cell = 8, .line = 15 },
        .{ .font = 16, .cell = 10, .line = 20 },
    };
    var scale: u16 = 1;
    while (scale <= maximum_raster_scale) : (scale += 1) {
        for (bases) |base| {
            if (font_pixels == base.font * scale and
                cell_width == base.cell * scale and
                cell_height == base.line * scale) return scale;
        }
    }
    return null;
}

fn contentConfig(cell_width: u16, cell_height: u16, atlas_extent: u16) terminal.Config {
    const raster_bytes = @as(usize, atlas_extent) * @as(usize, atlas_extent);
    return .{
        .cell_size = .{ .width = cell_width, .height = cell_height },
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
        .atlas = .{ .width = atlas_extent, .height = atlas_extent, .entry_capacity = 256 },
        .shaped_capacity = 32,
        .raster_bytes = raster_bytes,
        .command_capacity = command_capacity,
        .incremental_row_capacity = limits.maximum_rows,
        .incremental_command_capacity = incremental_command_capacity,
    };
}

/// Returns the native host ABI version.
pub export fn howl_native_host_version() u32 {
    return 8;
}

/// Reports the shared maintained-client row envelope.
pub export fn howl_native_host_maximum_rows() u32 {
    return limits.maximum_rows;
}

/// Reports the shared maintained-client column envelope.
pub export fn howl_native_host_maximum_columns() u32 {
    return limits.maximum_columns;
}

const NativeInterrupt = struct {
    allocator: std.mem.Allocator,
    transport: *client.Interrupt,
};

/// Caller cancels first, joins every worker, then destroys this borrowed token.
pub export fn howl_native_interrupt_create() ?*InterruptHandle {
    const allocator = std.heap.c_allocator;
    const value = allocator.create(NativeInterrupt) catch return null;
    const transport = client.Interrupt.init(allocator) catch {
        allocator.destroy(value);
        return null;
    };
    value.* = .{ .allocator = allocator, .transport = transport };
    // zig-audit: acknowledge ptr_cast
    // reason: The opaque FFI handle preserves this exact NativeInterrupt allocation.
    return @ptrCast(value);
}

/// Cancels remote transport I/O.
pub export fn howl_native_interrupt_cancel(raw: ?*InterruptHandle) i32 {
    const value = nativeInterruptFromRaw(raw) orelse return 1;
    value.transport.cancel() catch return 2;
    return 0;
}

/// Releases the token after every borrower has retired; null is a no-op.
pub export fn howl_native_interrupt_destroy(raw: ?*InterruptHandle) void {
    const value = nativeInterruptFromRaw(raw) orelse return;
    const allocator = value.allocator;
    value.transport.deinit();
    allocator.destroy(value);
}

fn nativeInterruptFromRaw(raw: ?*InterruptHandle) ?*NativeInterrupt {
    const value = raw orelse return null;
    // zig-audit: acknowledge ptr_cast
    // reason: Only interrupt_create produces this live FFI allocation.
    // zig-audit: acknowledge align_cast
    // reason: The matching constructor preserves NativeInterrupt alignment.
    return @ptrCast(@alignCast(value));
}

fn interruptFromRaw(raw: ?*InterruptHandle) ?*client.Interrupt {
    return if (nativeInterruptFromRaw(raw)) |value| value.transport else null;
}

/// Returns the minimum caller output capacity for a host packet.
pub export fn howl_native_host_output_minimum_bytes() usize {
    return output_minimum_bytes;
}

/// Returns the pending image refill byte count, or zero when absent.
pub export fn howl_native_host_image_refill_size(raw: ?*HostHandle) usize {
    const raw_host = raw orelse return 0;
    // zig-audit: acknowledge ptr_cast
    // reason: The FFI contract supplies the original live handle from the matching native constructor; this cast preserves that allocation's address and lifetime.
    // zig-audit: acknowledge align_cast
    // reason: The FFI caller must return the matching constructor's original live allocation; recovering its concrete owner asserts that preserved alignment.
    const host: *Host = @ptrCast(@alignCast(raw_host));
    const pending = host.pending_image orelse return 0;
    const pixels = imageRefillPixelBytes(pending.external.size) catch return 0;
    return std.math.add(usize, image_refill_header_bytes, pixels) catch 0;
}

/// Copies a requested image refill into caller-owned bounded output.
pub export fn howl_native_host_fetch_image_refill(
    raw: ?*HostHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const raw_host = raw orelse return 2;
    // zig-audit: acknowledge ptr_cast
    // reason: The FFI contract supplies the original live handle from the matching native constructor; this cast preserves that allocation's address and lifetime.
    // zig-audit: acknowledge align_cast
    // reason: The FFI caller must return the matching constructor's original live allocation; recovering its concrete owner asserts that preserved alignment.
    const host: *Host = @ptrCast(@alignCast(raw_host));
    const pending = host.pending_image orelse return 3;
    if (host.armed_live_after_revision != null) return 4;
    const required = howl_native_host_image_refill_size(raw);
    if (required == 0 or required > maximum_image_refill_bytes) return 4;
    if (output_capacity < required) return 1;


    var fetched = client.images.request(
        host.connection,
        host.allocator,
        pending.binding.image_id,
        pending.binding.generation,
    ) catch |failure| {
        if (failure == error.ServerRejected) host.pending_image = null;
        return imageRefillFetchFailureCode(failure);
    };
    defer fetched.deinit();
    if (fetched.width != pending.external.size.width or
        fetched.height != pending.external.size.height or
        fetched.pixels.len != required - image_refill_header_bytes or
        pending.external.format != .rgba8)
        return 4;
    writeImageRefill(
        output_ptr[0..required],
        pending,
        fetched.pixels,
    ) catch return 4;
    output_len.* = required;
    return 0;
}

fn imageRefillFetchFailureCode(failure: client.images.Error) i32 {
    // The Host only asks for exact ids/generations that came from one accepted
    // immutable graphics snapshot. A normal endpoint rejection therefore means
    // canonical graphics moved before this serial refill reached its resource.
    if (failure == error.ServerRejected) return 5;
    return switch (classifyFailure(failure)) {
        .transport => 6,
        .canceled => 7,
        .stale => 8,
        .permanent => 4,
    };
}

const FailureClass = enum(u8) {
    permanent = 1,
    transport = 2,
    canceled = 3,
    stale = 4,
};

fn classifyFailure(failure: ClassifiedFailure) FailureClass {
    return switch (failure) {
        error.ConnectionCanceled => .canceled,
        error.StaleServerIncarnation,
        error.SessionNotFound,
        error.InstanceNotFound,
        error.Unavailable,
        => .stale,
        error.SocketConnectFailed,
        error.SocketConnectTimedOut,
        error.SocketReadFailed,
        error.SocketWriteFailed,
        error.SocketShutdownFailed,
        error.ConnectionClosed,
        => .transport,
        else => .permanent,
    };
}

fn resetCreateDiagnostic(output_len: *usize) void {
    output_len.* = 0;
}

fn writeFailureText(
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    class: FailureClass,
    message: []const u8,
) void {
    if (output_capacity == 0) return;
    output_ptr[0] = @backingInt(class);
    const length = @min(output_capacity - 1, message.len);
    if (length != 0) @memcpy(output_ptr[1 .. 1 + length], message[0..length]);
    output_len.* = 1 + length;
}

fn writeCreateDiagnostic(
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    message: []const u8,
) void {
    writeFailureText(output_ptr, output_capacity, output_len, .permanent, message);
}

fn writeCreateStageFailure(
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    stage: []const u8,
    failure: ClassifiedFailure,
) void {
    if (output_capacity <= 1) {
        writeFailureText(output_ptr, output_capacity, output_len, classifyFailure(failure), &.{});
        return;
    }
    var buffer: [255]u8 = undefined;
    const rendered = std.fmt.bufPrint(&buffer, "{s}:{s}", .{ stage, @errorName(failure) }) catch &.{};
    writeFailureText(output_ptr, output_capacity, output_len, classifyFailure(failure), rendered);
}

fn writeConnectDiagnostic(
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    failure: ClassifiedFailure,
    diagnostic: client.ConnectDiagnostic,
) void {
    var buffer: [255]u8 = undefined;
    const rendered = std.fmt.bufPrint(
        &buffer,
        "{s} stage={s} os_error={d} poll_interrupts={d}",
        .{ @errorName(failure), @tagName(diagnostic.stage), diagnostic.os_error, diagnostic.poll_interrupts },
    ) catch &.{};
    writeFailureText(output_ptr, output_capacity, output_len, classifyFailure(failure), rendered);
}

fn writeManagedConnectDiagnostic(
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    owner_stage: []const u8,
    failure: ClassifiedFailure,
    diagnostic: client.ConnectDiagnostic,
) void {
    var buffer: [255]u8 = undefined;
    const rendered = std.fmt.bufPrint(
        &buffer,
        "{s}:{s} stage={s} os_error={d} poll_interrupts={d}",
        .{ owner_stage, @errorName(failure), @tagName(diagnostic.stage), diagnostic.os_error, diagnostic.poll_interrupts },
    ) catch &.{};
    writeFailureText(output_ptr, output_capacity, output_len, classifyFailure(failure), rendered);
}

fn controlFailureCode(failure: ClassifiedFailure) i32 {
    return switch (classifyFailure(failure)) {
        .transport => 5,
        .canceled => 6,
        .stale => 7,
        .permanent => 2,
    };
}

fn observeFailureCode(failure: ClassifiedFailure) i32 {
    return switch (classifyFailure(failure)) {
        .transport => 7,
        .canceled => 9,
        .stale => 10,
        .permanent => 4,
    };
}

fn connectManagedInstance(
    allocator: std.mem.Allocator,
    server_endpoint: []const u8,
    server_id: u64,
    session_id: u64,
    instance_id: u64,
    interrupt: ?*client.Interrupt,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*client.Connection {
    var server_diagnostic: server_client.ConnectDiagnostic = .{};
    const attached = server_client.attach(allocator, .{
        .endpoint = server_endpoint,
        .server_id = server_id,
        .session_id = session_id,
        .instance_id = instance_id,
    }, &server_diagnostic, interrupt) catch |failure| {
        writeManagedConnectDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            "server_attach",
            failure,
            server_diagnostic,
        );
        return null;
    };

    return attached;
}

fn createHost(
    connection: *client.Connection,
    primary_ptr: [*]const u8,
    primary_len: usize,
    fallback_ptr: [*]const u8,
    fallback_len: usize,
    secondary_fallback_ptr: ?[*]const u8,
    secondary_fallback_len: usize,
    font_pixels: u16,
    cell_width: u16,
    cell_height: u16,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*HostHandle {
    const raster_scale = maintainedRasterScale(font_pixels, cell_width, cell_height) orelse {
        writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_raster_scale");
        connection.deinit();
        return null;
    };
    const atlas_extent = std.math.mul(u16, atlas_base_extent, raster_scale) catch |failure| {
        writeCreateStageFailure(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "atlas_extent", failure);
        connection.deinit();
        return null;
    };
    const allocator = std.heap.c_allocator;
    var connection_live = true;
    defer if (connection_live) connection.deinit();

    var raw_cache = client.rich.RawCache.init(allocator);
    var raw_cache_live = true;
    defer if (raw_cache_live) raw_cache.deinit();

    var fallback_storage: [2][]const u8 = undefined;
    var fallback_count: usize = 0;
    if (fallback_len != 0) {
        fallback_storage[fallback_count] = fallback_ptr[0..fallback_len];
        fallback_count += 1;
    }
    if (secondary_fallback_len != 0) {
        const pointer = secondary_fallback_ptr orelse {
            writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "secondary_fallback_pointer");
            return null;
        };
        fallback_storage[fallback_count] = pointer[0..secondary_fallback_len];
        fallback_count += 1;
    }
    const fallbacks = fallback_storage[0..fallback_count];
    const fonts = text.FontSet.init(allocator, .{
        .primary = primary_ptr[0..primary_len],
        .fallbacks = fallbacks,
        .size = .{ .pixels = font_pixels },
    }) catch |failure| {
        writeCreateStageFailure(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "font_set", failure);
        return null;
    };
    var fonts_live = true;
    defer if (fonts_live) fonts.deinit();

    const terminal_renderer = terminal.initPrivate(
        allocator,
        terminal.FontFaces.single(fonts),
        contentConfig(cell_width, cell_height, atlas_extent),
    ) catch |failure| {
        writeCreateStageFailure(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "terminal_canvas", failure);
        return null;
    };
    var renderer_live = true;
    defer if (renderer_live) terminal.deinit(terminal_renderer);

    const observation_scratch = allocator.alloc(u8, observation_scratch_bytes) catch |failure| {
        writeCreateStageFailure(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "observation_scratch", failure);
        return null;
    };
    var scratch_live = true;
    defer if (scratch_live) allocator.free(observation_scratch);

    const host = allocator.create(Host) catch |failure| {
        writeCreateStageFailure(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "host_alloc", failure);
        return null;
    };
    host.* = .{
        .allocator = allocator,
        .connection = connection,
        .raw_cache = raw_cache,
        .cell_size = .{ .width = cell_width, .height = cell_height },
        .fonts = fonts,
        .renderer = terminal_renderer,
        .observation_scratch = observation_scratch,
    };
    connection_live = false;
    raw_cache_live = false;
    fonts_live = false;
    renderer_live = false;
    scratch_live = false;
    // zig-audit: acknowledge ptr_cast
    // reason: The FFI contract supplies the original live handle from the matching native constructor; this cast preserves that allocation's address and lifetime.
    return @ptrCast(host);
}

/// Creates a host attached to an exact Server/Session/Instance occurrence.
pub export fn howl_native_host_create_managed(
    server_endpoint_ptr: [*]const u8,
    server_endpoint_len: usize,
    server_id: u64,
    session_id: u64,
    instance_id: u64,
    primary_ptr: [*]const u8,
    primary_len: usize,
    fallback_ptr: [*]const u8,
    fallback_len: usize,
    secondary_fallback_ptr: ?[*]const u8,
    secondary_fallback_len: usize,
    font_pixels: u16,
    cell_width: u16,
    cell_height: u16,
    interrupt_raw: ?*InterruptHandle,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*HostHandle {
    resetCreateDiagnostic(diagnostic_len);
    if (server_endpoint_len == 0 or server_id == 0 or session_id == 0 or instance_id == 0 or primary_len == 0 or
        font_pixels == 0 or cell_width == 0 or cell_height == 0)
    {
        writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_arguments");
        return null;
    }
    const allocator = std.heap.c_allocator;
    const connection = connectManagedInstance(
        allocator,
        server_endpoint_ptr[0..server_endpoint_len],
        server_id,
        session_id,
        instance_id,
        interruptFromRaw(interrupt_raw),
        diagnostic_ptr,
        diagnostic_capacity,
        diagnostic_len,
    ) orelse return null;
    return createHost(
        connection,
        primary_ptr,
        primary_len,
        fallback_ptr,
        fallback_len,
        secondary_fallback_ptr,
        secondary_fallback_len,
        font_pixels,
        cell_width,
        cell_height,
        diagnostic_ptr,
        diagnostic_capacity,
        diagnostic_len,
    );
}

fn createControlFromConnection(
    connection_value: *client.Connection,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*ControlHandle {
    const allocator = std.heap.c_allocator;
    const connection = connection_value;
    var connection_live = true;
    defer if (connection_live) connection.deinit();
    const control = allocator.create(Control) catch |failure| {
        writeCreateStageFailure(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "control_alloc", failure);
        return null;
    };
    control.* = .{ .allocator = allocator, .connection = connection };
    connection_live = false;
    // zig-audit: acknowledge ptr_cast
    // reason: The FFI contract supplies the original live handle from the matching native constructor; this cast preserves that allocation's address and lifetime.
    return @ptrCast(control);
}

/// Creates control attached to the exact managed terminal occurrence.
pub export fn howl_native_control_create_managed(
    server_endpoint_ptr: [*]const u8,
    server_endpoint_len: usize,
    server_id: u64,
    session_id: u64,
    instance_id: u64,
    interrupt_raw: ?*InterruptHandle,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) ?*ControlHandle {
    resetCreateDiagnostic(diagnostic_len);
    if (server_endpoint_len == 0 or server_id == 0 or session_id == 0 or instance_id == 0) {
        writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_arguments");
        return null;
    }
    const allocator = std.heap.c_allocator;
    const connection = connectManagedInstance(
        allocator,
        server_endpoint_ptr[0..server_endpoint_len],
        server_id,
        session_id,
        instance_id,
        interruptFromRaw(interrupt_raw),
        diagnostic_ptr,
        diagnostic_capacity,
        diagnostic_len,
    ) orelse return null;
    return createControlFromConnection(
        connection,
        diagnostic_ptr,
        diagnostic_capacity,
        diagnostic_len,
    );
}

fn writeJsonIdentity(writer: *std.Io.Writer, value: u64) !void {
    var buffer: [32]u8 = undefined;
    const rendered = try std.fmt.bufPrint(&buffer, "{d}", .{value});
    try std.json.Stringify.value(rendered, .{}, writer);
}

fn writeServerLaunchReceipt(writer: *std.Io.Writer, server_id: u64, session_id: u64, instance_id: u64) !void {
    try writer.writeAll("{\"schema\":\"howl.server.launch/v1\",\"server_id\":");
    try writeJsonIdentity(writer, server_id);
    try writer.writeAll(",\"session_id\":");
    try writeJsonIdentity(writer, session_id);
    try writer.writeAll(",\"instance_id\":");
    try writeJsonIdentity(writer, instance_id);
    try writer.writeByte('}');
}

/// Copies the Server catalogue into caller-owned bounded output.
pub export fn howl_native_server_tree(
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    interrupt_raw: ?*InterruptHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) i32 {
    output_len.* = 0;
    resetCreateDiagnostic(diagnostic_len);
    if (endpoint_len == 0 or output_capacity == 0) {
        writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_arguments");
        return 1;
    }

    const allocator = std.heap.c_allocator;
    var connect_diagnostic: server_client.ConnectDiagnostic = .{};
    var connection = server_client.Connection.connectCancelable(
        allocator,
        endpoint_ptr[0..endpoint_len],
        &connect_diagnostic,
        interruptFromRaw(interrupt_raw),
    ) catch |failure| {
        writeManagedConnectDiagnostic(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            "server_tree_connect",
            failure,
            connect_diagnostic,
        );
        return 2;
    };
    defer connection.deinit();

    var tree = connection.observeTree(0) catch |failure| {
        writeCreateStageFailure(
            diagnostic_ptr,
            diagnostic_capacity,
            diagnostic_len,
            "server_tree",
            failure,
        );
        return 3;
    };
    defer tree.deinit();

    var writer: std.Io.Writer = .fixed(output_ptr[0..output_capacity]);
    writer.writeAll("{\"schema\":\"howl.server.tree/v1\",\"server_id\":") catch return 4;
    writeJsonIdentity(&writer, tree.status.server_id) catch return 4;
    writer.writeAll(",\"tree_revision\":") catch return 4;
    writeJsonIdentity(&writer, tree.status.tree_revision) catch return 4;
    writer.writeAll(",\"sessions\":[") catch return 4;
    for (tree.sessions, 0..) |session, session_index| {
        if (session_index != 0) writer.writeByte(',') catch return 4;
        writer.writeAll("{\"session_id\":") catch return 4;
        writeJsonIdentity(&writer, session.id) catch return 4;
        writer.writeAll(",\"name\":") catch return 4;
        std.json.Stringify.value(session.name, .{}, &writer) catch return 4;
        writer.writeAll(",\"instances\":[") catch return 4;
        for (session.instances, 0..) |instance, instance_index| {
            if (instance_index != 0) writer.writeByte(',') catch return 4;
            writer.writeAll("{\"instance_id\":") catch return 4;
            writeJsonIdentity(&writer, instance.instance_id) catch return 4;
            writer.writeAll(",\"state\":") catch return 4;
            std.json.Stringify.value(@tagName(instance.state), .{}, &writer) catch return 4;
            writer.writeByte('}') catch return 4;
        }
        writer.writeAll("]}") catch return 4;
    }
    writer.writeAll("]}") catch return 4;
    output_len.* = writer.buffered().len;
    return 0;
}

/// Launches one Server Instance, optionally creating its named Session first.
/// A failed Instance launch closes only the Session created by this call.
/// All identities are returned as decimal strings to preserve full u64 values.
pub export fn howl_native_server_launch(
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    expected_server_id: u64,
    session_id: u64,
    name_ptr: [*]const u8,
    name_len: usize,
    shell_ptr: [*]const u8,
    shell_len: usize,
    interrupt_raw: ?*InterruptHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
    diagnostic_ptr: [*]u8,
    diagnostic_capacity: usize,
    diagnostic_len: *usize,
) i32 {
    output_len.* = 0;
    resetCreateDiagnostic(diagnostic_len);
    const name = name_ptr[0..name_len];
    const shell = shell_ptr[0..shell_len];
    if (endpoint_len == 0 or expected_server_id == 0 or output_capacity < 192 or
        shell.len == 0 or shell.len > server_client.protocol.maximum_shell_bytes or
        std.mem.indexOfScalar(u8, shell, 0) != null or
        (session_id == 0 and (name_len == 0 or name_len > server_client.protocol.maximum_session_name_bytes)) or
        (session_id != 0 and name_len != 0))
    {
        writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_launch_arguments");
        return 1;
    }
    if (session_id == 0) server_client.protocol.validateSessionName(name) catch {
        writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "invalid_session_name");
        return 1;
    };

    const allocator = std.heap.c_allocator;
    var connect_diagnostic: server_client.ConnectDiagnostic = .{};
    var connection = server_client.Connection.connectCancelable(
        allocator,
        endpoint_ptr[0..endpoint_len],
        &connect_diagnostic,
        interruptFromRaw(interrupt_raw),
    ) catch |failure| {
        writeManagedConnectDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "server_launch_connect", failure, connect_diagnostic);
        return 2;
    };
    defer connection.deinit();
    if (connection.serverId() != expected_server_id) {
        writeFailureText(diagnostic_ptr, diagnostic_capacity, diagnostic_len, .stale, "server_incarnation_changed");
        return 3;
    }

    const created_session = session_id == 0;
    const selected_session = if (created_session) connection.createSession(name) catch |failure| {
        writeCreateStageFailure(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "session_create", failure);
        return 4;
    } else session_id;
    const identity = connection.createInstance(.{
        .session_id = selected_session,
        .shell = shell,
        .rows = 24,
        .columns = 40,
        .history_rows = 4096,
    }) catch |failure| {
        if (created_session) connection.closeSession(selected_session) catch {
            writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "instance_create_failed_session_cleanup_failed");
            return 5;
        };
        writeCreateStageFailure(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "instance_create", failure);
        return 5;
    };

    var writer: std.Io.Writer = .fixed(output_ptr[0..output_capacity]);
    writeServerLaunchReceipt(&writer, expected_server_id, identity.session_id, identity.instance_id) catch {
        // This is precluded by the 192-byte output floor, but cleanup remains
        // exact if the private FFI receipt format ever outgrows that floor.
        connection.closeInstance(identity) catch {
            writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "launch_receipt_failed_instance_cleanup_failed");
            return 6;
        };
        if (created_session) connection.closeSession(selected_session) catch {
            writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "launch_receipt_failed_session_cleanup_failed");
            return 6;
        };
        writeCreateDiagnostic(diagnostic_ptr, diagnostic_capacity, diagnostic_len, "launch_receipt_failed");
        return 6;
    };
    output_len.* = writer.buffered().len;
    return 0;
}

/// Releases owned control resources; null is a no-op.
pub export fn howl_native_control_destroy(raw: ?*ControlHandle) void {
    const raw_control = raw orelse return;
    // zig-audit: acknowledge ptr_cast
    // reason: The FFI contract supplies the original live handle from the matching native constructor; this cast preserves that allocation's address and lifetime.
    // zig-audit: acknowledge align_cast
    // reason: The FFI caller must return the matching constructor's original live allocation; recovering its concrete owner asserts that preserved alignment.
    const control: *Control = @ptrCast(@alignCast(raw_control));
    const allocator = control.allocator;
    control.connection.deinit();
    control.* = undefined;
    allocator.destroy(control);
}

/// Sends bounded committed text through semantic control.
pub export fn howl_native_control_committed_text(
    raw: ?*ControlHandle,
    bytes_ptr: [*]const u8,
    bytes_len: usize,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    client.actions.committedText(control.connection, bytes_ptr[0..bytes_len]) catch |failure| return controlFailureCode(failure);
    return 0;
}

/// Sends bounded paste bytes through semantic control.
pub export fn howl_native_control_paste(
    raw: ?*ControlHandle,
    bytes_ptr: [*]const u8,
    bytes_len: usize,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    client.actions.paste(control.connection, bytes_ptr[0..bytes_len]) catch |failure| return controlFailureCode(failure);
    return 0;
}

/// Validates and sends one named physical key.
pub export fn howl_native_control_named_key(
    raw: ?*ControlHandle,
    key_value: u8,
    action_value: u8,
    modifiers: u8,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    if (key_value < 1 or key_value > 58 or action_value < 1 or action_value > 3) return 3;
    client.actions.namedKey(
        control.connection,
        @fromBackingInt(@intCast(key_value)),
        @fromBackingInt(@intCast(action_value)),
        modifiers,
    ) catch |failure| return controlFailureCode(failure);
    return 0;
}

/// Validates and sends one Unicode physical key.
pub export fn howl_native_control_unicode_key(
    raw: ?*ControlHandle,
    scalar: u32,
    action_value: u8,
    modifiers: u8,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    if (action_value < 1 or action_value > 3) return 3;
    client.actions.unicodeKey(
        control.connection,
        scalar,
        @fromBackingInt(@intCast(action_value)),
        modifiers,
    ) catch |failure| return controlFailureCode(failure);
    return 0;
}

/// Validates and sends one explicit focus transition.
pub export fn howl_native_control_focus(raw: ?*ControlHandle, focus_value: u8) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    if (focus_value < 1 or focus_value > 2) return 3;
    client.actions.focus(control.connection, @fromBackingInt(@intCast(focus_value))) catch |failure| return controlFailureCode(failure);
    return 0;
}

/// Requests explicit terminal geometry through semantic control.
pub export fn howl_native_control_resize(
    raw: ?*ControlHandle,
    rows: u16,
    columns: u16,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    client.actions.resize(control.connection, rows, columns) catch |failure| return controlFailureCode(failure);
    return 0;
}

/// Validates and sends one child signal.
pub export fn howl_native_control_signal(raw: ?*ControlHandle, signal_value: u8) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    const signal: protocol.Signal = switch (signal_value) {
        1 => .hangup,
        2 => .interrupt,
        3 => .resize_notify,
        9 => .kill,
        15 => .terminate,
        else => return 3,
    };
    client.actions.signal(control.connection, signal) catch |failure| return controlFailureCode(failure);
    return 0;
}

/// Copies current interaction facts into caller-owned bounded output.
pub export fn howl_native_control_interaction_state(
    raw: ?*ControlHandle,
    output_ptr: [*]u8,
    output_capacity: usize,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    if (output_capacity < interaction_packet_bytes) return 3;
    const state = server_native.interaction(control.connection) catch |failure| return controlFailureCode(failure);
    @memcpy(output_ptr[0..interaction_packet_bytes], std.mem.asBytes(&state));
    return 0;
}

/// Validates and sends one semantic mouse event.
pub export fn howl_native_control_mouse(
    raw: ?*ControlHandle,
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
    const control = controlFromRaw(raw) orelse return 1;
    if (kind_value < 1 or kind_value > 4 or button_value > 5 or pixels_present > 1)
        return 3;
    client.actions.mouse(control.connection, .{
        .kind = @fromBackingInt(@intCast(kind_value)),
        .button = @fromBackingInt(@intCast(button_value)),
        .modifiers = modifiers,
        .buttons_down = buttons_down,
        .row = row,
        .column = column,
        .pixel_x = if (pixels_present != 0) pixel_x else null,
        .pixel_y = if (pixels_present != 0) pixel_y else null,
    }) catch |failure| return controlFailureCode(failure);
    return 0;
}

/// Copies requested terminal text into caller-owned bounded output.
pub export fn howl_native_control_text_extract(
    raw: ?*ControlHandle,
    start_row: i32,
    start_column: u16,
    end_row: i32,
    end_column: u16,
    columns: u16,
    alternate_screen: u8,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    const control = controlFromRaw(raw) orelse return 1;
    if (columns == 0 or alternate_screen > 1) return 3;
    const selected = client.selection.extract(
        control.connection,
        control.allocator,
        .{
            .anchor = .{ .row = start_row, .column = start_column },
            .focus = .{ .row = end_row, .column = end_column },
            .columns = columns,
            .alternate_screen = alternate_screen == 1,
        },
    ) catch |failure| return controlFailureCode(failure);
    defer control.allocator.free(selected);
    if (selected.len > output_capacity) return 4;
    @memcpy(output_ptr[0..selected.len], selected);
    output_len.* = selected.len;
    return 0;
}

fn controlFromRaw(raw: ?*ControlHandle) ?*Control {
    const value = raw orelse return null;
    // zig-audit: acknowledge ptr_cast
    // reason: The FFI contract supplies the original live handle from the matching native constructor; this cast preserves that allocation's address and lifetime.
    // zig-audit: acknowledge align_cast
    // reason: The FFI caller must return the matching constructor's original live allocation; recovering its concrete owner asserts that preserved alignment.
    return @ptrCast(@alignCast(value));
}

/// Releases host resources; null is a no-op.
pub export fn howl_native_host_destroy(raw: ?*HostHandle) void {
    const raw_host = raw orelse return;
    // zig-audit: acknowledge ptr_cast
    // reason: The FFI contract supplies the original live handle from the matching native constructor; this cast preserves that allocation's address and lifetime.
    // zig-audit: acknowledge align_cast
    // reason: The FFI caller must return the matching constructor's original live allocation; recovering its concrete owner asserts that preserved alignment.
    const host: *Host = @ptrCast(@alignCast(raw_host));
    const allocator = host.allocator;
    const observation_scratch = host.observation_scratch;
    terminal.deinit(host.renderer);
    host.fonts.deinit();
    host.raw_cache.deinit();
    host.connection.deinit();
    host.* = undefined;
    allocator.free(observation_scratch);
    allocator.destroy(host);
}

/// Private, version-locked blocking observation call.
///
/// `output` is caller-owned. No pointer into native presentation memory survives
/// this call. `residency` is a packed list of exact resources which the Flutter
/// backend successfully retained from the previous presented frame.
pub export fn howl_native_host_set_live_observe_pipeline(
    raw: ?*HostHandle,
    enabled: u8,
) i32 {
    if (enabled > 1) return 3;
    const raw_host = raw orelse return 2;
    // zig-audit: acknowledge ptr_cast
    // reason: The FFI contract supplies the original live handle from the matching native constructor; this cast preserves that allocation's address and lifetime.
    // zig-audit: acknowledge align_cast
    // reason: The FFI caller must return the matching constructor's original live allocation; recovering its concrete owner asserts that preserved alignment.
    const host: *Host = @ptrCast(@alignCast(raw_host));
    if (host.armed_live_after_revision != null) return 4;
    if (host.live_resync_required) return 4;
    host.live_observe_pipeline = enabled == 1;
    return 0;
}

/// Observes one frame into caller-owned bounded packet storage.
pub export fn howl_native_host_observe(
    raw: ?*HostHandle,
    after_revision: u64,
    history_offset: u32,
    residency_ptr: ?[*]const u8,
    residency_len: usize,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    if (output_capacity < output_minimum_bytes) return 1;
    const raw_host = raw orelse return 2;
    // zig-audit: acknowledge ptr_cast
    // reason: The FFI contract supplies the original live handle from the matching native constructor; this cast preserves that allocation's address and lifetime.
    // zig-audit: acknowledge align_cast
    // reason: The FFI caller must return the matching constructor's original live allocation; recovering its concrete owner asserts that preserved alignment.
    const host: *Host = @ptrCast(@alignCast(raw_host));
    const residency_bytes: []const u8 = if (residency_len == 0)
        &.{}
    else
        (residency_ptr orelse return 3)[0..residency_len];
    const written = observe(
        host,
        after_revision,
        history_offset,
        residency_bytes,
        output_ptr[0..output_capacity],
    ) catch |failure| {
        return switch (failure) {
            error.BufferTooSmall => 1,
            error.InvalidResidency => 3,
            error.ImageRefillRequired => 5,
            else => |value| observeFailureCode(value),
        };
    };
    output_len.* = written;
    return 0;
}

const interaction_packet_bytes: usize = @sizeOf(vt_native.c.hvt_interaction);
comptime {
    if (vt_native.c.HVT_NATIVE_VERSION != 1 or interaction_packet_bytes != 16 or
        @sizeOf(server_native.c.hvt_interaction) != interaction_packet_bytes)
        @compileError("Flutter must forward the reviewed VT native interaction record");
}

fn receiveRich(
    host: *Host,
    allocator: std.mem.Allocator,
    after_revision: u64,
    history_offset: u32,
) !client.rich.Snapshot {
    if (host.armed_live_after_revision != null) return error.InvalidHost;
    return client.rich.requestPacked(
        host.connection,
        allocator,
        after_revision,
        history_offset,
    );
}

fn receiveLiveRich(
    host: *Host,
    after_revision: u64,
    history_offset: u32,
) !client.rich.View {
    if (!host.live_observe_pipeline or history_offset != 0) return error.InvalidHost;
    if (host.armed_live_after_revision) |armed_after| {
        if (after_revision != armed_after) return error.InvalidHost;
    } else {
        // A new native live observer owns no reusable row baseline. Its Dart
        // lifecycle starts at revision zero. An image-refill pause is the one
        // bounded exception: decoding already advanced the private RawCache,
        // while Dart deliberately retries the last *presented* revision after
        // installing the requested resource. Resynchronize with one complete
        // delta-lane fallback instead of guessing that stale caller revision.
        if (after_revision != 0 and !host.live_resync_required)
            return error.InvalidHost;
        try host.raw_cache.sendDeltaRequest(host.connection, 0, 0);
        host.live_resync_required = false;
    }
    const snapshot = try host.raw_cache.receive(host.connection);
    host.armed_live_after_revision = null;
    return snapshot;
}

fn observe(
    host: *Host,
    after_revision: u64,
    history_offset: u32,
    residency_bytes: []const u8,
    output: []u8,
) ClassifiedFailure!usize {
    if (output.len < output_minimum_bytes) return error.BufferTooSmall;
    const residency = try decodeResidencies(host, residency_bytes);
    var scratch = std.heap.FixedBufferAllocator.init(host.observation_scratch);
    const frame_allocator = scratch.allocator();

    const live = host.live_observe_pipeline and history_offset == 0;
    var owned_rich: ?client.rich.Snapshot = null;
    defer if (owned_rich) |*value| value.deinit();
    var cached_rich: ?client.rich.View = null;
    if (live) {
        cached_rich = try receiveLiveRich(host, after_revision, history_offset);
    } else {
        owned_rich = try receiveRich(host, frame_allocator, after_revision, history_offset);
    }
    var rich_view = if (cached_rich) |value| value else owned_rich.?.view();
    const begin = rich_view.begin;

    const surface = try surfaceSize(begin.terminal.rows, begin.terminal.columns, host.cell_size);
    try updateHostRendererRich(host, &rich_view);
    const frame = terminal.frame(host.renderer, residency, .{
        .uploads = &host.frame_uploads,
        .removals = &host.frame_removals,
        .commands = &host.frame_commands,
        .pixels = &host.frame_pixels,
    }) catch |failure| switch (failure) {
        error.MissingExternalResource => {
            try prepareImageRefill(host, residency);
            if (live) host.live_resync_required = true;
            return error.ImageRefillRequired;
        },
        else => return failure,
    };
    host.pending_image = null;

    var writer = Writer{ .bytes = output };
    try writeHostHeader(&writer, transportedFacts(begin));
    const hcr_start = writer.offset;
    try writeGlobalHeader(&writer, surface);
    try writeFrame(&writer, frame, 1);
    const hcr_end = writer.offset;
    const hcr_len = hcr_end - hcr_start;
    if (hcr_end > render_packet_budget) return error.BufferTooSmall;
    for (0..begin.terminal.rows) |row| {
        const shape = client.selection.rowShapeRich(&rich_view, @intCast(row)) orelse
            return error.InvalidFrame;
        const encoded_shape = shape.content_end_exclusive |
            (if (shape.wrapped) @as(u16, 1) << 15 else 0);
        try writer.writeU16(encoded_shape);
    }
    const semantic_start = writer.offset;
    if (semantic_start + semantic_capacity > output.len)
        return error.BufferTooSmall;
    const semantic = client.view.writeVisibleRichText(
        &rich_view,
        output[semantic_start .. semantic_start + semantic_capacity],
    );
    writer.offset = semantic_start + semantic.bytes_written;
    try appendTitle(&writer, rich_view.properties.title);
    const total = writer.offset;
    if (total > std.math.maxInt(u32) or hcr_len > std.math.maxInt(u32) or
        semantic.bytes_written > std.math.maxInt(u32))
        return error.IntegerOverflow;
    const total_bytes: *[4]u8 = output[8..12];
    std.mem.writeInt(u32, total_bytes, @intCast(total), .little);
    const hcr_bytes: *[4]u8 = output[16..20];
    std.mem.writeInt(u32, hcr_bytes, @intCast(hcr_len), .little);
    if (semantic.truncated) {
        const flags_bytes: *[4]u8 = output[20..24];
        const flags = std.mem.readInt(u32, flags_bytes, .little) | (1 << 6);
        std.mem.writeInt(u32, flags_bytes, flags, .little);
    }
    const semantic_bytes: *[4]u8 = output[60..64];
    std.mem.writeInt(u32, semantic_bytes, @intCast(semantic.bytes_written), .little);
    if (host.live_observe_pipeline and history_offset == 0) {
        try host.raw_cache.sendDeltaRequest(host.connection, begin.revision, 0);
        host.armed_live_after_revision = begin.revision;
        host.live_resync_required = false;
    }
    return total;
}

fn updateHostRendererRich(
    host: *Host,
    view: *const client.rich.View,
) !void {
    const graphics = view.graphics;
    if (graphics.images.len > maximum_terminal_images)
        return error.InvalidHost;
    var candidate: [maximum_terminal_images]HostImageBinding = undefined;
    const bindings = transported_render.planExternalImageBindings(
        host.image_bindings[0..host.image_binding_count],
        terminal.usage(host.renderer),
        graphics.images,
        &candidate,
    ) catch return error.InvalidHost;
    try transported_render.updateRichWithImageBindings(host.renderer, view, bindings);
    @memcpy(host.image_bindings[0..bindings.len], bindings);
    host.image_binding_count = bindings.len;
}

fn findImageBindingByResource(
    bindings: []const HostImageBinding,
    resource: terminal.ResourceRef,
) ?HostImageBinding {
    for (bindings) |binding| {
        if (binding.resource.resource == resource.resource and
            binding.resource.generation == resource.generation)
            return binding;
    }
    return null;
}

fn selectPendingImage(
    bindings: []const HostImageBinding,
    missing: []const terminal.FrameExternalResource,
) !PendingImage {
    if (missing.len == 0 or missing.len > bindings.len) return error.InvalidHost;
    var selected: ?PendingImage = null;
    for (missing, 0..) |value, index| {
        if (value.format != .rgba8) return error.InvalidHost;
        const binding = findImageBindingByResource(bindings, value.resource) orelse
            return error.InvalidHost;
        if (index == 0) selected = .{ .binding = binding, .external = value };
    }
    return selected orelse error.InvalidHost;
}

fn prepareImageRefill(
    host: *Host,
    residency: []const terminal.Residency,
) !void {
    const missing = try terminal.missingExternalResources(
        host.renderer,
        residency,
        &host.missing_external,
    );
    const pending = try selectPendingImage(
        host.image_bindings[0..host.image_binding_count],
        missing,
    );
    const pixel_bytes = try imageRefillPixelBytes(pending.external.size);
    if (pixel_bytes == 0) return error.InvalidHost;
    host.pending_image = pending;
}

fn imageRefillPixelBytes(size: terminal.Size) !usize {
    const stride = std.math.mul(usize, size.width, 4) catch return error.InvalidFrame;
    return std.math.mul(usize, stride, size.height) catch return error.InvalidFrame;
}

fn writeImageRefill(
    output: []u8,
    pending: PendingImage,
    pixels: []const u8,
) !void {
    const expected_pixels = try imageRefillPixelBytes(pending.external.size);
    if (pixels.len != expected_pixels or
        pending.external.stride != @as(usize, pending.external.size.width) * 4)
        return error.InvalidFrame;
    const expected_total = try checkedAdd(image_refill_header_bytes, pixels.len);
    if (output.len != expected_total or expected_total > std.math.maxInt(u32) or
        pixels.len > std.math.maxInt(u32) or
        pending.external.stride > std.math.maxInt(u32))
        return error.InvalidFrame;

    var writer = Writer{ .bytes = output };
    const magic = try writer.need(4);
    @memcpy(magic, "HIR1");
    try writer.writeU16(2);
    try writer.writeU16(image_refill_header_bytes);
    try writer.writeU32(@intCast(expected_total));
    try writer.writeU32(@intCast(pixels.len));
    try writer.writeU64(@backingInt(pending.external.resource.resource));
    try writer.writeU64(@backingInt(pending.external.resource.generation));
    try writer.writeU32(pending.binding.image_id);
    try writer.writeU8(@backingInt(pending.external.format));
    try writer.writeU8(0);
    try writer.writeU16(pending.external.size.width);
    try writer.writeU16(pending.external.size.height);
    try writer.writeU16(0);
    try writer.writeU32(@intCast(pending.external.stride));
    try writer.writeU64(pending.binding.generation);
    if (writer.offset != image_refill_header_bytes) return error.InvalidFrame;
    @memcpy(try writer.need(pixels.len), pixels);
    if (writer.offset != output.len) return error.InvalidFrame;
}

fn surfaceSize(rows: u16, columns: u16, cell_size: terminal.Size) !terminal.Size {
    if (rows == 0 or columns == 0 or cell_size.width == 0 or cell_size.height == 0)
        return error.InvalidFrame;
    return .{
        .width = std.math.mul(u16, columns, cell_size.width) catch return error.InvalidFrame,
        .height = std.math.mul(u16, rows, cell_size.height) catch return error.InvalidFrame,
    };
}

test "native host surface follows configured presentation lattice" {
    try std.testing.expectEqualDeep(
        terminal.Size{ .width = 408, .height = 705 },
        try surfaceSize(47, 51, .{ .width = 8, .height = 15 }),
    );
    try std.testing.expectEqualDeep(
        terminal.Size{ .width = 510, .height = 948 },
        try surfaceSize(79, 85, .{ .width = 6, .height = 12 }),
    );
    try std.testing.expectError(
        error.InvalidFrame,
        surfaceSize(1, std.math.maxInt(u16), .{ .width = 2, .height = 1 }),
    );
}

test "native host dense presentation budgets raster and commands together" {
    try std.testing.expectEqual(@as(usize, 768 * 768), pixel_capacity);
    try std.testing.expectEqual(@as(usize, 32 * 1024 * 1024), observation_scratch_bytes);
    try std.testing.expect(observation_scratch_bytes >= protocol.maximum_text_snapshot_bytes * 8);
    try std.testing.expectEqual(@as(?u16, 1), maintainedRasterScale(16, 10, 20));
    try std.testing.expectEqual(@as(?u16, 2), maintainedRasterScale(18, 12, 24));
    try std.testing.expectEqual(@as(?u16, 3), maintainedRasterScale(36, 24, 45));
    try std.testing.expectEqual(@as(?u16, 4), maintainedRasterScale(64, 40, 80));
    try std.testing.expectEqual(@as(?u16, null), maintainedRasterScale(17, 10, 20));
    try std.testing.expectEqual(limits.maximum_frame_commands, command_capacity);
    try std.testing.expect(command_capacity >= limits.maximum_cells + client.view.maximum_image_placements + 1);
    try std.testing.expectEqual(@as(u32, limits.maximum_rows), howl_native_host_maximum_rows());
    try std.testing.expectEqual(@as(u32, limits.maximum_columns), howl_native_host_maximum_columns());
    try std.testing.expectEqual(
        maximum_non_command_packet_bytes + command_capacity * command_record_bytes +
            selection_rows_capacity + semantic_capacity + title_capacity,
        output_minimum_bytes,
    );
    try std.testing.expect(output_minimum_bytes < 8 * 1024 * 1024);
    try std.testing.expectEqual(@as(usize, 7), maximum_terminal_images);
    try std.testing.expectEqual(maximum_frame_resources, terminal.maximum_frame_resources);
}

test "native host distinguishes superseded image generation and failure classes" {
    try std.testing.expectEqual(@as(i32, 5), imageRefillFetchFailureCode(error.ServerRejected));
    try std.testing.expectEqual(@as(i32, 4), imageRefillFetchFailureCode(error.UnexpectedFrame));
    try std.testing.expectEqual(@as(i32, 6), imageRefillFetchFailureCode(error.ConnectionClosed));
    try std.testing.expectEqual(@as(i32, 7), imageRefillFetchFailureCode(error.ConnectionCanceled));
    try std.testing.expectEqual(@as(i32, 5), controlFailureCode(error.ConnectionClosed));
    try std.testing.expectEqual(@as(i32, 6), controlFailureCode(error.ConnectionCanceled));
    try std.testing.expectEqual(@as(i32, 7), controlFailureCode(error.StaleServerIncarnation));
    try std.testing.expectEqual(@as(i32, 2), controlFailureCode(error.UnexpectedFrame));
    try std.testing.expectEqual(@as(i32, 7), observeFailureCode(error.ConnectionClosed));
    try std.testing.expectEqual(@as(i32, 9), observeFailureCode(error.ConnectionCanceled));
    try std.testing.expectEqual(@as(i32, 10), observeFailureCode(error.SessionNotFound));
    try std.testing.expectEqual(@as(i32, 4), observeFailureCode(error.UnexpectedFrame));
}

test "native host selects one exact refill from multiple missing images" {
    const first_local = terminal.ResourceRef{
        .resource = try terminal.ResourceId.init(2),
        .generation = @fromBackingInt(5),
    };
    const second_local = terminal.ResourceRef{
        .resource = try terminal.ResourceId.init(3),
        .generation = @fromBackingInt(7),
    };
    const bindings = [_]HostImageBinding{
        .{ .image_id = 11, .generation = 5, .resource = first_local },
        .{ .image_id = 12, .generation = 7, .resource = second_local },
    };
    var missing = [_]terminal.FrameExternalResource{
        .{
            .resource = first_local,
            .format = .rgba8,
            .size = .{ .width = 2, .height = 2 },
            .stride = 8,
        },
        .{
            .resource = second_local,
            .format = .rgba8,
            .size = .{ .width = 3, .height = 1 },
            .stride = 12,
        },
    };
    const selected = try selectPendingImage(&bindings, &missing);
    try std.testing.expectEqualDeep(bindings[0], selected.binding);
    try std.testing.expectEqualDeep(missing[0], selected.external);

    const first_resource = missing[0].resource;
    missing[0].resource = .{
        .resource = try terminal.ResourceId.init(99),
        .generation = first_resource.generation,
    };
    try std.testing.expectError(error.InvalidHost, selectPendingImage(&bindings, &missing));
    missing[0].resource = first_resource;

    const second_resource = missing[1].resource;
    const unknown = terminal.ResourceRef{
        .resource = try terminal.ResourceId.init(9),
        .generation = @fromBackingInt(1),
    };
    missing[1].resource = unknown;
    try std.testing.expectError(error.InvalidHost, selectPendingImage(&bindings, &missing));
    missing[1].resource = second_resource;

    missing[1].format = .alpha8;
    try std.testing.expectError(error.InvalidHost, selectPendingImage(&bindings, &missing));
    try std.testing.expectError(
        error.InvalidHost,
        selectPendingImage(&bindings, missing[0..0]),
    );
}

test "native host image refill packet carries exact terminal identity" {
    const local_resource = terminal.ResourceRef{
        .resource = try terminal.ResourceId.init(7),
        .generation = @fromBackingInt(11),
    };
    const pending = PendingImage{
        .binding = .{
            .image_id = 17,
            .generation = 23,
            .resource = local_resource,
        },
        .external = .{
            .resource = local_resource,
            .format = .rgba8,
            .size = .{ .width = 2, .height = 2 },
            .stride = 8,
        },
    };
    const pixels = [_]u8{
        1,  2,  3,  4,
        5,  6,  7,  8,
        9,  10, 11, 12,
        13, 14, 15, 16,
    };
    var packet: [image_refill_header_bytes + pixels.len]u8 = undefined;
    try writeImageRefill(&packet, pending, &pixels);

    try std.testing.expectEqualSlices(u8, "HIR1", packet[0..4]);
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, packet[4..6], .little));
    try std.testing.expectEqual(
        @as(u16, image_refill_header_bytes),
        std.mem.readInt(u16, packet[6..8], .little),
    );
    try std.testing.expectEqual(
        @as(u32, packet.len),
        std.mem.readInt(u32, packet[8..12], .little),
    );
    try std.testing.expectEqual(
        @as(u32, pixels.len),
        std.mem.readInt(u32, packet[12..16], .little),
    );
    try std.testing.expectEqual(
        @backingInt(local_resource.resource),
        std.mem.readInt(u64, packet[16..24], .little),
    );
    try std.testing.expectEqual(
        @backingInt(local_resource.generation),
        std.mem.readInt(u64, packet[24..32], .little),
    );
    try std.testing.expectEqual(@as(u32, 17), std.mem.readInt(u32, packet[32..36], .little));
    try std.testing.expectEqual(@backingInt(terminal.ResourceFormat.rgba8), packet[36]);
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, packet[38..40], .little));
    try std.testing.expectEqual(@as(u16, 2), std.mem.readInt(u16, packet[40..42], .little));
    try std.testing.expectEqual(@as(u32, 8), std.mem.readInt(u32, packet[44..48], .little));
    try std.testing.expectEqual(@as(u64, 23), std.mem.readInt(u64, packet[48..56], .little));
    try std.testing.expectEqualSlices(u8, &pixels, packet[image_refill_header_bytes..]);

    try std.testing.expectError(
        error.InvalidFrame,
        writeImageRefill(packet[0 .. packet.len - 1], pending, &pixels),
    );
}

const HostFacts = struct {
    revision: u64,
    terminal_revision: u64,
    stream_closed: bool,
    child_exited: bool,
    leader_present: bool,
    you_are_leader: bool,
    alternate_screen: bool,
    rows: u16,
    columns: u16,
    cursor_row: u16,
    cursor_column: u16,
    cursor_visible: bool,
    history_offset: u32,
    history_count: u32,
    history_row_base: u32,
};

fn transportedFacts(begin: client.view.Begin) HostFacts {
    return .{
        .revision = begin.revision,
        .terminal_revision = begin.terminal.revision,
        .stream_closed = begin.stream_closed,
        .child_exited = begin.child_exited,
        .leader_present = begin.leader_present,
        .you_are_leader = begin.you_are_leader,
        .alternate_screen = begin.terminal.alternate_screen,
        .rows = begin.terminal.rows,
        .columns = begin.terminal.columns,
        .cursor_row = begin.terminal.cursor_row,
        .cursor_column = begin.terminal.cursor_column,
        .cursor_visible = begin.terminal.cursor_visible,
        .history_offset = begin.terminal.history_offset,
        .history_count = begin.terminal.history_count,
        .history_row_base = begin.terminal.history_row_base,
    };
}

fn writeHostHeader(writer: *Writer, begin: HostFacts) !void {
    const magic = try writer.need(4);
    @memcpy(magic, "HNH1");
    try writer.writeU16(4);
    try writer.writeU16(host_header_bytes);
    try writer.writeU32(0); // total bytes, patched after serialization
    try writer.writeU32(host_header_bytes);
    try writer.writeU32(0); // terminal-frame payload bytes, patched after serialization
    var flags: u32 = 0;
    if (begin.alternate_screen) flags |= 1 << 0;
    if (begin.stream_closed) flags |= 1 << 1;
    if (begin.child_exited) flags |= 1 << 2;
    if (begin.leader_present) flags |= 1 << 3;
    if (begin.you_are_leader) flags |= 1 << 4;
    if (begin.cursor_visible) flags |= 1 << 5;
    try writer.writeU32(flags);
    try writer.writeU64(begin.revision);
    try writer.writeU64(begin.terminal_revision);
    try writer.writeU32(begin.history_offset);
    try writer.writeU32(begin.history_count);
    try writer.writeU32(begin.history_row_base);
    try writer.writeU16(begin.rows);
    try writer.writeU16(begin.columns);
    try writer.writeU16(begin.cursor_row);
    try writer.writeU16(begin.cursor_column);
    try writer.writeU32(0); // semantic UTF-8 bytes, patched after serialization
    try writer.writeU32(0); // terminal title bytes, patched after serialization
    if (writer.offset != host_header_bytes) return error.InvalidFrame;
}

fn appendTitle(writer: *Writer, title: ?[]const u8) HostPacketError!void {
    if (title) |value| {
        if (value.len > title_capacity) return error.InvalidFrame;
        @memcpy(try writer.need(value.len), value);
        std.mem.writeInt(u32, writer.bytes[64..68], @intCast(value.len), .little);
        const flags = std.mem.readInt(u32, writer.bytes[20..24], .little);
        std.mem.writeInt(u32, writer.bytes[20..24], flags | (1 << 7), .little);
    }
}

fn writeGlobalHeader(writer: *Writer, surface: terminal.Size) !void {
    const magic = try writer.need(4);
    @memcpy(magic, "HCR1");
    try writer.writeU16(2);
    try writer.writeU16(global_header_bytes);
    try writer.writeU16(surface.width);
    try writer.writeU16(surface.height);
    try writer.writeU32(0);
}

const residency_record_bytes: usize = 24;

fn decodeResidencies(host: *Host, bytes: []const u8) HostPacketError![]const terminal.Residency {
    if (bytes.len % residency_record_bytes != 0) return error.InvalidResidency;
    const count = bytes.len / residency_record_bytes;
    if (count > host.residencies.len) return error.InvalidResidency;
    for (0..count) |index| {
        const at = bytes[index * residency_record_bytes ..][0..residency_record_bytes];
        const resource_encoded: u64 = std.mem.readInt(u64, at[0..8], .little);
        const generation: u64 = std.mem.readInt(u64, at[8..16], .little);
        const format_value = at[16];
        const width: u16 = std.mem.readInt(u16, at[18..20], .little);
        const height: u16 = std.mem.readInt(u16, at[20..22], .little);
        if (generation == 0 or width == 0 or height == 0 or
            at[17] != 0 or std.mem.readInt(u16, at[22..24], .little) != 0 or
            format_value > @backingInt(terminal.ResourceFormat.rgba8))
            return error.InvalidResidency;
        const resource = terminal.ResourceId.fromEncoded(resource_encoded) catch
            return error.InvalidResidency;
        host.residencies[index] = .{
            .resource = .{
                .resource = resource,
                .generation = @fromBackingInt(@intCast(generation)),
            },
            .format = @fromBackingInt(@intCast(format_value)),
            .size = .{ .width = width, .height = height },
        };
    }
    return host.residencies[0..count];
}

const Writer = struct {
    bytes: []u8,
    offset: usize = 0,

    fn need(self: *Writer, count: usize) HostPacketError![]u8 {
        if (count > self.bytes.len -| self.offset) return error.BufferTooSmall;
        const result = self.bytes[self.offset .. self.offset + count];
        self.offset += count;
        return result;
    }

    fn zeroes(self: *Writer, count: usize) HostPacketError!void {
        @memset(try self.need(count), 0);
    }

    fn writeU8(self: *Writer, value: u8) HostPacketError!void {
        (try self.need(1))[0] = value;
    }

    fn writeU16(self: *Writer, value: u16) HostPacketError!void {
        const output: *[2]u8 = (try self.need(2))[0..2];
        std.mem.writeInt(u16, output, value, .little);
    }

    fn writeU32(self: *Writer, value: u32) HostPacketError!void {
        const output: *[4]u8 = (try self.need(4))[0..4];
        std.mem.writeInt(u32, output, value, .little);
    }

    fn writeI32(self: *Writer, value: i32) HostPacketError!void {
        const output: *[4]u8 = (try self.need(4))[0..4];
        std.mem.writeInt(i32, output, value, .little);
    }

    fn writeU64(self: *Writer, value: u64) HostPacketError!void {
        const output: *[8]u8 = (try self.need(8))[0..8];
        std.mem.writeInt(u64, output, value, .little);
    }
};

fn writeFrame(writer: *Writer, frame: terminal.Frame, flags: u32) !void {
    var resources: [maximum_frame_resources]terminal.ResourceView = undefined;
    const resource_count = try collectFrameResources(frame.commands, &resources);
    const resource_bytes = try checkedMul(resource_count, resource_record_bytes);
    const removal_bytes = try checkedMul(frame.removals.len, removal_record_bytes);
    const command_bytes = try checkedMul(frame.commands.len, command_record_bytes);
    const fixed = try checkedAdd(frame_header_bytes, resource_bytes);
    const fixed2 = try checkedAdd(fixed, removal_bytes);
    const fixed3 = try checkedAdd(fixed2, command_bytes);
    const record_bytes = try checkedAdd(fixed3, frame.pixels.len);
    if (record_bytes > std.math.maxInt(u32) or
        frame.commands.len > std.math.maxInt(u32) or
        frame.removals.len > std.math.maxInt(u32) or
        frame.pixels.len > std.math.maxInt(u32))
    {
        return error.IntegerOverflow;
    }

    try writer.writeU32(@intCast(record_bytes));
    try writer.writeU32(flags);
    try writer.writeU64(frame.revision);
    try writer.writeU32(@intCast(resource_count));
    try writer.writeU32(@intCast(frame.removals.len));
    try writer.writeU32(@intCast(frame.commands.len));
    try writer.writeU32(@intCast(frame.pixels.len));
    try writer.writeU32(@intCast(resource_bytes));
    try writer.writeU32(@intCast(removal_bytes));
    try writer.writeU32(@intCast(command_bytes));
    try writer.writeU32(0);

    for (resources[0..resource_count]) |resource|
        try writeResource(writer, resource, frame);
    for (frame.removals) |removal| {
        try writer.writeU64(@backingInt(removal.resource));
        try writer.writeU64(@backingInt(removal.generation));
    }
    for (frame.commands) |command|
        try writeCommand(writer, command, resources[0..resource_count]);
    const pixels = try writer.need(frame.pixels.len);
    @memcpy(pixels, frame.pixels);
}

fn collectFrameResources(
    commands: []const terminal.Command,
    output: *[maximum_frame_resources]terminal.ResourceView,
) !usize {
    var used: usize = 0;
    for (commands) |command| {
        const view: ?terminal.ResourceView = switch (command) {
            .solid => null,
            .alpha_mask => |value| value.resource,
            .rgba => |value| value.resource,
        };
        const resource = view orelse continue;
        var found = false;
        for (output[0..used]) |existing| {
            if (std.meta.eql(existing.resource, resource.resource)) {
                if (existing.format != resource.format or !std.meta.eql(existing.size, resource.size))
                    return error.InvalidFrame;
                found = true;
                break;
            }
        }
        if (found) continue;
        if (used >= output.len) return error.ResourceLimit;
        output[used] = resource;
        used += 1;
    }
    return used;
}

fn writeResource(
    writer: *Writer,
    resource: terminal.ResourceView,
    frame: terminal.Frame,
) !void {
    var upload: ?terminal.FrameResourceUpload = null;
    for (frame.uploads) |candidate| {
        if (std.meta.eql(candidate.resource, resource.resource)) {
            upload = candidate;
            break;
        }
    }
    try writer.writeU64(@backingInt(resource.resource.resource));
    try writer.writeU64(@backingInt(resource.resource.generation));
    try writer.writeU8(@backingInt(resource.format));
    try writer.writeU8(0);
    try writer.writeU16(resource.size.width);
    try writer.writeU16(resource.size.height);
    try writer.writeU16(0);
    if (upload) |value| {
        if (value.stride > std.math.maxInt(u32) or
            value.pixel_offset > std.math.maxInt(u32) or
            value.pixel_count > std.math.maxInt(u32)) return error.IntegerOverflow;
        try writer.writeU32(@intCast(value.stride));
        try writer.writeU32(@intCast(value.pixel_offset));
        try writer.writeU32(@intCast(value.pixel_count));
    } else {
        try writer.writeU32(0);
        try writer.writeU32(0);
        try writer.writeU32(0);
    }
    try writer.writeU32(0);
}

// Render owns command semantics; Flutter only packs its private 40-byte record
// and replaces exact resource identities with this frame's resource-table index.
// One stack record per command; no second command array or pixel borrow.
fn writeCommand(
    writer: *Writer,
    command: terminal.Command,
    resources: []const terminal.ResourceView,
) !void {
    var info: render_native.CommandInfo = undefined;
    render_native.commandInfo(command, &info);
    try writer.writeU8(info.tag);
    try writer.writeU8(if (info.tag == render_native.c.HRC_SOLID) 0xff else try frameResourceIndex(resources, info.resource, info.generation));
    try writer.writeU8(info.cursor_component);
    try writer.writeU8(0);
    try writer.writeU32(info.color_rgba);
    try writer.writeI32(info.destination_x);
    try writer.writeI32(info.destination_y);
    try writer.writeU16(info.destination_width);
    try writer.writeU16(info.destination_height);
    try writer.writeI32(info.clip_x);
    try writer.writeI32(info.clip_y);
    try writer.writeU16(info.clip_width);
    try writer.writeU16(info.clip_height);
    if (info.tag == render_native.c.HRC_SOLID) {
        // Preserve the private writer's single eight-byte unused source field.
        try writer.zeroes(8);
    } else {
        try writer.writeU16(info.source_x);
        try writer.writeU16(info.source_y);
        try writer.writeU16(info.source_width);
        try writer.writeU16(info.source_height);
    }
}

fn frameResourceIndex(
    resources: []const terminal.ResourceView,
    resource: u64,
    generation: u64,
) !u8 {
    for (resources, 0..) |candidate, index| {
        if (@backingInt(candidate.resource.resource) == resource and
            @backingInt(candidate.resource.generation) == generation) return @intCast(index);
    }
    return error.MissingResource;
}

fn checkedMul(left: usize, right: usize) HostPacketError!usize {
    return std.math.mul(usize, left, right) catch error.IntegerOverflow;
}

fn checkedAdd(left: usize, right: usize) HostPacketError!usize {
    return std.math.add(usize, left, right) catch error.IntegerOverflow;
}

test "Flutter private command packets preserve legacy bytes and bounded write prefixes" {
    const alpha = terminal.ResourceView{
        .resource = .{ .resource = @fromBackingInt(0x1122334455667788), .generation = @fromBackingInt(0xfffffffffffffff1) },
        .format = .alpha8,
        .size = .{ .width = 31, .height = 37 },
    };
    const rgba = terminal.ResourceView{
        .resource = .{ .resource = @fromBackingInt(0x8877665544332211), .generation = @fromBackingInt(0xfffffffffffffffe) },
        .format = .rgba8,
        .size = .{ .width = 29, .height = 31 },
        .source = .{ .x = 2, .y = 3, .width = 5, .height = 7 },
    };
    var cropped_alpha = alpha;
    cropped_alpha.source = .{ .x = 1, .y = 2, .width = 3, .height = 4 };
    const commands = [_]terminal.Command{
        .{ .solid = .{ .rect = .{ .x = -3, .y = 4, .width = 20, .height = 9 }, .color = .{ .r = 1, .g = 2, .b = 3, .a = 4 } } },
        .{ .alpha_mask = .{ .destination = .{ .x = -17, .y = 19, .width = 11, .height = 13 }, .clip = .{ .x = -5, .y = 20, .width = 4, .height = 6 }, .resource = alpha, .color = .{ .r = 1, .g = 2, .b = 127, .a = 128 }, .cursor_component = true } },
        .{ .rgba = .{ .destination = .{ .x = 7, .y = -9, .width = 17, .height = 19 }, .clip = .{ .x = 8, .y = -8, .width = 11, .height = 12 }, .resource = rgba } },
        .{ .alpha_mask = .{ .destination = .{ .x = -17, .y = 19, .width = 11, .height = 13 }, .clip = .{ .x = -5, .y = 20, .width = 4, .height = 6 }, .resource = cropped_alpha, .color = .{ .r = 1, .g = 2, .b = 127, .a = 128 } } },
    };
    // Legacy private packet golden: deliberately reordered resources, signed
    // origins, full/cropped sources, both cursor values, every command kind.
    const expected = [_]u8{ 0x00, 0xff, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0xfd, 0xff, 0xff, 0xff, 0x04, 0x00, 0x00, 0x00, 0x14, 0x00, 0x09, 0x00, 0xfd, 0xff, 0xff, 0xff, 0x04, 0x00, 0x00, 0x00, 0x14, 0x00, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x01, 0x01, 0x00, 0x01, 0x02, 0x7f, 0x80, 0xef, 0xff, 0xff, 0xff, 0x13, 0x00, 0x00, 0x00, 0x0b, 0x00, 0x0d, 0x00, 0xfb, 0xff, 0xff, 0xff, 0x14, 0x00, 0x00, 0x00, 0x04, 0x00, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1f, 0x00, 0x25, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00, 0xf7, 0xff, 0xff, 0xff, 0x11, 0x00, 0x13, 0x00, 0x08, 0x00, 0x00, 0x00, 0xf8, 0xff, 0xff, 0xff, 0x0b, 0x00, 0x0c, 0x00, 0x02, 0x00, 0x03, 0x00, 0x05, 0x00, 0x07, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x02, 0x7f, 0x80, 0xef, 0xff, 0xff, 0xff, 0x13, 0x00, 0x00, 0x00, 0x0b, 0x00, 0x0d, 0x00, 0xfb, 0xff, 0xff, 0xff, 0x14, 0x00, 0x00, 0x00, 0x04, 0x00, 0x06, 0x00, 0x01, 0x00, 0x02, 0x00, 0x03, 0x00, 0x04, 0x00 };
    const resources = [_]terminal.ResourceView{ rgba, alpha };
    var output: [expected.len + 8]u8 = @splat(0xa5);
    var writer = Writer{ .bytes = &output };
    for (commands) |command| try writeCommand(&writer, command, &resources);
    try std.testing.expectEqual(expected.len, writer.offset);
    try std.testing.expectEqualSlices(u8, &expected, output[0..writer.offset]);
    for (output[writer.offset..]) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
    for (0..expected.len) |capacity| {
        @memset(&output, 0xa5);
        writer = .{ .bytes = output[0..capacity] };
        var rejected = false;
        for (commands) |command| {
            writeCommand(&writer, command, &resources) catch |failure| {
                try std.testing.expectEqual(error.BufferTooSmall, failure);
                rejected = true;
                break;
            };
        }
        try std.testing.expect(rejected);
        // Legacy field boundaries: solid's final padding is one eight-byte write;
        // sampled commands finish with four two-byte source coordinates.
        const solid_ends = [_]usize{ 1, 2, 3, 4, 8, 12, 16, 18, 20, 24, 28, 30, 32, 40 };
        const sampled_ends = [_]usize{ 1, 2, 3, 4, 8, 12, 16, 18, 20, 24, 28, 30, 32, 34, 36, 38, 40 };
        var legacy_offset: usize = 0;
        for (0..commands.len) |command_index| {
            const ends: []const usize = if (command_index == 0) &solid_ends else &sampled_ends;
            for (ends) |end| {
                const offset = command_index * command_record_bytes + end;
                if (offset <= capacity) legacy_offset = offset;
            }
        }
        try std.testing.expectEqual(legacy_offset, writer.offset);
        try std.testing.expectEqualSlices(u8, expected[0..writer.offset], output[0..writer.offset]);
        for (output[writer.offset..]) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
    }
    var stale = alpha;
    stale.resource.generation = @fromBackingInt(2);
    @memset(&output, 0xa5);
    writer = .{ .bytes = &output };
    try std.testing.expectError(error.MissingResource, writeCommand(&writer, commands[1], &.{stale}));
    try std.testing.expectEqual(@as(usize, 1), writer.offset);
    try std.testing.expectEqual(@as(u8, 1), output[0]);
    for (output[1..]) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
}

test "Flutter visible-text legacy golden preserves concealment, visual rows and scalar truncation" {
    var value = try vt_native.Terminal.initWithHistory(std.testing.allocator, 5, 16, 6);
    defer value.deinit();
    try std.testing.expect((try value.feed("Á中\x1b[8mSECRET\x1b[0mB\r\n\r\nX")).stateChanged());
    const view = value.semanticView(0);
    const expected = "Á中      B\n\nX";
    var output: [64]u8 = @splat(0xa5);
    const full = try vt_native.queries.writeVisibleText(&view, &output);
    try std.testing.expectEqualStrings(expected, output[0..full.bytes_written]);
    try std.testing.expect(!full.truncated);
    for (0..expected.len + 1) |capacity| {
        @memset(&output, 0xa5);
        const result = try vt_native.queries.writeVisibleText(&view, output[0..capacity]);
        try std.testing.expectEqualSlices(u8, expected[0..result.bytes_written], output[0..result.bytes_written]);
        try std.testing.expect(std.unicode.utf8ValidateSlice(output[0..result.bytes_written]));
        try std.testing.expectEqual(capacity < expected.len, result.truncated);
        for (output[result.bytes_written..]) |byte| try std.testing.expectEqual(@as(u8, 0xa5), byte);
    }
    try std.testing.expectEqual(@as(u16, 10), (try vt_native.queries.rowShape(&view, 0)).content_end_exclusive);
}
