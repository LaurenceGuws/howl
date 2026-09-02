const std = @import("std");
const client = @import("howl_client");
const protocol = @import("howl_session").protocol;
const text = @import("howl_text");
const canvas = @import("canvas");
const terminal = @import("terminal");

const host_header_bytes: usize = 64;
const global_header_bytes: usize = 32;
const frame_header_bytes: usize = 48;
const resource_record_bytes: usize = 48;
const removal_record_bytes: usize = 24;
const command_record_bytes: usize = 40;
const maximum_frame_resources: usize = 8;
const output_minimum_bytes: usize = 256 * 1024;
const command_capacity: usize = 4096;
const pixel_capacity: usize = 64 * 1024;

const HostPacketError = error{
    BufferTooSmall,
    ResourceLimit,
    MissingResource,
    InvalidFrame,
    IntegerOverflow,
    InvalidResidency,
    InvalidHost,
};

const HostHandle = opaque {};
const ControlHandle = opaque {};

const Control = struct {
    allocator: std.mem.Allocator,
    connection: client.Connection,
};

const Host = struct {
    allocator: std.mem.Allocator,
    connection: client.Connection,
    fonts: *text.FontSet,
    content: *terminal.Content,
    composer: canvas.Composer,
    source: canvas.SourceId,
    frame_uploads: [maximum_frame_resources]canvas.FrameResourceUpload = undefined,
    frame_removals: [maximum_frame_resources]canvas.FrameResourceRef = undefined,
    frame_commands: [command_capacity]canvas.Command = undefined,
    frame_pixels: [pixel_capacity]u8 = undefined,
    residencies: [maximum_frame_resources]canvas.Residency = undefined,
    live_observe_pipeline: bool = false,
    armed_live_after_revision: ?u64 = null,
};

fn contentConfig() terminal.ContentConfig {
    return .{
        .cell_size = .{ .width = 10, .height = 20 },
        .shape_cache = .{
            .entry_capacity = 256,
            .scalar_capacity = 512,
            .glyph_capacity = 512,
            .max_sequence_scalars = 16,
        },
        .atlas = .{ .width = 128, .height = 128, .entry_capacity = 256 },
        .shaped_capacity = 32,
        .raster_bytes = 16 * 1024,
        .command_capacity = command_capacity,
    };
}

pub export fn howl_native_host_version() u32 {
    return 1;
}

pub export fn howl_native_host_create(
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
    primary_ptr: [*]const u8,
    primary_len: usize,
    fallback_ptr: [*]const u8,
    fallback_len: usize,
    secondary_fallback_ptr: ?[*]const u8,
    secondary_fallback_len: usize,
) ?*HostHandle {
    if (endpoint_len == 0 or primary_len == 0) return null;
    const allocator = std.heap.c_allocator;
    var connection = client.Connection.connect(allocator, endpoint_ptr[0..endpoint_len]) catch return null;
    errdefer connection.deinit();
    var fallback_storage: [2][]const u8 = undefined;
    var fallback_count: usize = 0;
    if (fallback_len != 0) {
        fallback_storage[fallback_count] = fallback_ptr[0..fallback_len];
        fallback_count += 1;
    }
    if (secondary_fallback_len != 0) {
        const pointer = secondary_fallback_ptr orelse return null;
        fallback_storage[fallback_count] = pointer[0..secondary_fallback_len];
        fallback_count += 1;
    }
    const fallbacks = fallback_storage[0..fallback_count];
    // `FontSet.init` copies every path during this call.
    const fonts = text.FontSet.init(allocator, .{
        .primary = primary_ptr[0..primary_len],
        .fallbacks = fallbacks,
        .size = .{ .pixels = 16 },
    }) catch return null;
    errdefer fonts.deinit();
    const content = terminal.initContent(allocator, fonts, contentConfig()) catch return null;
    errdefer terminal.deinitContent(content);
    var composer = canvas.Composer.init(allocator, .{
        .sources = 1,
        .retained_resources = maximum_frame_resources,
        .retained_commands = command_capacity,
        .retained_pixel_bytes = pixel_capacity,
        .composition_sources = 1,
        .candidate_resources = maximum_frame_resources,
        .candidate_commands = command_capacity,
        .candidate_pixel_bytes = pixel_capacity,
    }) catch return null;
    errdefer composer.deinit();
    const source = composer.registerSource() catch return null;
    const host = allocator.create(Host) catch return null;
    host.* = .{
        .allocator = allocator,
        .connection = connection,
        .fonts = fonts,
        .content = content,
        .composer = composer,
        .source = source,
    };
    return @ptrCast(host);
}

pub export fn howl_native_control_create(
    endpoint_ptr: [*]const u8,
    endpoint_len: usize,
) ?*ControlHandle {
    if (endpoint_len == 0) return null;
    const allocator = std.heap.c_allocator;
    var connection = client.Connection.connect(allocator, endpoint_ptr[0..endpoint_len]) catch
        return null;
    errdefer connection.deinit();
    const control = allocator.create(Control) catch return null;
    control.* = .{ .allocator = allocator, .connection = connection };
    return @ptrCast(control);
}

pub export fn howl_native_control_destroy(raw: ?*ControlHandle) void {
    const raw_control = raw orelse return;
    const control: *Control = @ptrCast(@alignCast(raw_control));
    const allocator = control.allocator;
    control.connection.deinit();
    control.* = undefined;
    allocator.destroy(control);
}

pub export fn howl_native_control_committed_text(
    raw: ?*ControlHandle,
    bytes_ptr: [*]const u8,
    bytes_len: usize,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    client.actions.committedText(&control.connection, bytes_ptr[0..bytes_len]) catch return 2;
    return 0;
}

pub export fn howl_native_control_paste(
    raw: ?*ControlHandle,
    bytes_ptr: [*]const u8,
    bytes_len: usize,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    client.actions.paste(&control.connection, bytes_ptr[0..bytes_len]) catch return 2;
    return 0;
}

pub export fn howl_native_control_named_key(
    raw: ?*ControlHandle,
    key_value: u8,
    action_value: u8,
    modifiers: u8,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    if (key_value < 1 or key_value > 58 or action_value < 1 or action_value > 3) return 3;
    client.actions.namedKey(
        &control.connection,
        @fromBackingInt(@intCast(key_value)),
        @fromBackingInt(@intCast(action_value)),
        modifiers,
    ) catch return 2;
    return 0;
}

pub export fn howl_native_control_unicode_key(
    raw: ?*ControlHandle,
    scalar: u32,
    action_value: u8,
    modifiers: u8,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    if (action_value < 1 or action_value > 3) return 3;
    client.actions.unicodeKey(
        &control.connection,
        scalar,
        @fromBackingInt(@intCast(action_value)),
        modifiers,
    ) catch return 2;
    return 0;
}

pub export fn howl_native_control_focus(raw: ?*ControlHandle, focus_value: u8) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    if (focus_value < 1 or focus_value > 2) return 3;
    client.actions.focus(&control.connection, @fromBackingInt(@intCast(focus_value))) catch return 2;
    return 0;
}

pub export fn howl_native_control_resize(
    raw: ?*ControlHandle,
    rows: u16,
    columns: u16,
) i32 {
    const control = controlFromRaw(raw) orelse return 1;
    client.actions.resize(&control.connection, rows, columns) catch return 2;
    return 0;
}

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
    client.actions.signal(&control.connection, signal) catch return 2;
    return 0;
}

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
    client.actions.mouse(&control.connection, .{
        .kind = @fromBackingInt(@intCast(kind_value)),
        .button = @fromBackingInt(@intCast(button_value)),
        .modifiers = modifiers,
        .buttons_down = buttons_down,
        .row = row,
        .column = column,
        .pixel_x = if (pixels_present != 0) pixel_x else null,
        .pixel_y = if (pixels_present != 0) pixel_y else null,
    }) catch return 2;
    return 0;
}

fn controlFromRaw(raw: ?*ControlHandle) ?*Control {
    const value = raw orelse return null;
    return @ptrCast(@alignCast(value));
}

pub export fn howl_native_host_destroy(raw: ?*HostHandle) void {
    const raw_host = raw orelse return;
    const host: *Host = @ptrCast(@alignCast(raw_host));
    const allocator = host.allocator;
    host.composer.deinit();
    terminal.deinitContent(host.content);
    host.fonts.deinit();
    host.connection.deinit();
    host.* = undefined;
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
    const host: *Host = @ptrCast(@alignCast(raw_host));
    if (host.armed_live_after_revision != null) return 4;
    host.live_observe_pipeline = enabled == 1;
    return 0;
}

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
    ) catch |failure| return switch (failure) {
        error.BufferTooSmall => 1,
        error.InvalidResidency => 3,
        else => 4,
    };
    output_len.* = written;
    return 0;
}

fn receiveRich(
    host: *Host,
    after_revision: u64,
    history_offset: u32,
) !client.rich.Snapshot {
    if (host.armed_live_after_revision) |armed_after| {
        if (!host.live_observe_pipeline or history_offset != 0 or after_revision != armed_after)
            return error.InvalidHost;
        const snapshot = try client.rich.receive(&host.connection, host.allocator);
        host.armed_live_after_revision = null;
        return snapshot;
    }
    return client.rich.request(
        &host.connection,
        host.allocator,
        after_revision,
        history_offset,
    );
}

fn observe(
    host: *Host,
    after_revision: u64,
    history_offset: u32,
    residency_bytes: []const u8,
    output: []u8,
) !usize {
    if (output.len < output_minimum_bytes) return error.BufferTooSmall;
    const residency = try decodeResidencies(host, residency_bytes);

    var rich = try receiveRich(host, after_revision, history_offset);
    defer rich.deinit();
    const begin = rich.begin;
    if (host.live_observe_pipeline and history_offset == 0) {
        try client.rich.sendRequest(&host.connection, begin.revision, 0);
        host.armed_live_after_revision = begin.revision;
    }
    const view = try client.view.project(host.allocator, &rich);
    defer client.view.deinit(view);

    const surface = canvas.Size{
        .width = std.math.mul(u16, begin.columns, 10) catch return error.InvalidFrame,
        .height = std.math.mul(u16, begin.rows, 20) catch return error.InvalidFrame,
    };
    const placement = canvas.Composer.Placement{
        .source = host.source,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = surface.width, .height = surface.height },
    };
    try host.composer.setComposition(.{
        .surface = surface,
        .sources = &.{placement},
        .focused_source = host.source,
    });
    const update = try terminal.takeContentUpdate(host.content, view, .{
        .pane = 1,
        .source = host.source,
        .visible_set_revision = 1,
        .lifecycle_revision = 1,
    });
    try host.composer.apply(host.source, update);
    const frame = try host.composer.frame(residency, .{
        .uploads = &host.frame_uploads,
        .removals = &host.frame_removals,
        .commands = &host.frame_commands,
        .pixels = &host.frame_pixels,
    });

    var writer = Writer{ .bytes = output };
    try writeHostHeader(&writer, begin);
    const hcr_start = writer.offset;
    try writeGlobalHeader(&writer, surface);
    try writeFrame(&writer, frame, 1);
    const total = writer.offset;
    const hcr_len = total - hcr_start;
    if (total > std.math.maxInt(u32) or hcr_len > std.math.maxInt(u32))
        return error.IntegerOverflow;
    const total_bytes: *[4]u8 = @ptrCast(output[8..12].ptr);
    std.mem.writeInt(u32, total_bytes, @intCast(total), .little);
    const hcr_bytes: *[4]u8 = @ptrCast(output[16..20].ptr);
    std.mem.writeInt(u32, hcr_bytes, @intCast(hcr_len), .little);
    return total;
}

fn writeHostHeader(writer: *Writer, begin: client.view.Begin) !void {
    const magic = try writer.need(4);
    @memcpy(magic, "HNH1");
    try writer.writeU16(1);
    try writer.writeU16(host_header_bytes);
    try writer.writeU32(0); // total bytes, patched after serialization
    try writer.writeU32(host_header_bytes);
    try writer.writeU32(0); // Canvas payload bytes, patched after serialization
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
    try writer.writeU32(0);
    if (writer.offset != host_header_bytes) return error.InvalidFrame;
}

fn writeGlobalHeader(writer: *Writer, surface: canvas.Size) !void {
    const magic = try writer.need(4);
    @memcpy(magic, "HCR1");
    try writer.writeU16(1);
    try writer.writeU16(global_header_bytes);
    try writer.writeU32(1);
    try writer.writeU32(1);
    try writer.writeU16(surface.width);
    try writer.writeU16(surface.height);
    try writer.zeroes(global_header_bytes - 20);
}

const residency_record_bytes: usize = 32;

fn decodeResidencies(host: *Host, bytes: []const u8) HostPacketError![]const canvas.Residency {
    if (bytes.len % residency_record_bytes != 0) return error.InvalidResidency;
    const count = bytes.len / residency_record_bytes;
    if (count > host.residencies.len) return error.InvalidResidency;
    for (0..count) |index| {
        const at = bytes[index * residency_record_bytes ..][0..residency_record_bytes];
        const source: u64 = std.mem.readInt(u64, at[0..8], .little);
        const resource_encoded: u64 = std.mem.readInt(u64, at[8..16], .little);
        const generation: u64 = std.mem.readInt(u64, at[16..24], .little);
        const format_value = at[24];
        const width: u16 = std.mem.readInt(u16, at[26..28], .little);
        const height: u16 = std.mem.readInt(u16, at[28..30], .little);
        if (source == 0 or generation == 0 or width == 0 or height == 0 or
            format_value > @backingInt(canvas.ResourceFormat.rgba8))
            return error.InvalidResidency;
        const resource = canvas.ResourceId.fromEncoded(resource_encoded) catch
            return error.InvalidResidency;
        if (resource.isShared()) return error.InvalidResidency;
        host.residencies[index] = .{
            .resource = canvas.FrameResourceRef.init(
                @fromBackingInt(@intCast(source)),
                resource,
                @fromBackingInt(@intCast(generation)),
            ) catch return error.InvalidResidency,
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
        const output: *[2]u8 = @ptrCast((try self.need(2)).ptr);
        std.mem.writeInt(u16, output, value, .little);
    }

    fn writeU32(self: *Writer, value: u32) HostPacketError!void {
        const output: *[4]u8 = @ptrCast((try self.need(4)).ptr);
        std.mem.writeInt(u32, output, value, .little);
    }

    fn writeI32(self: *Writer, value: i32) HostPacketError!void {
        const output: *[4]u8 = @ptrCast((try self.need(4)).ptr);
        std.mem.writeInt(i32, output, value, .little);
    }

    fn writeU64(self: *Writer, value: u64) HostPacketError!void {
        const output: *[8]u8 = @ptrCast((try self.need(8)).ptr);
        std.mem.writeInt(u64, output, value, .little);
    }
};

fn writeFrame(writer: *Writer, frame: canvas.Composer.Frame, flags: u32) !void {
    var resources: [maximum_frame_resources]canvas.FrameResourceView = undefined;
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
    try writer.writeU64(@backingInt(frame.revision));
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
        try writer.writeU64(@backingInt(removal.source));
        try writer.writeU64(@backingInt(removal.resource));
        try writer.writeU64(@backingInt(removal.generation));
    }
    for (frame.commands) |command|
        try writeCommand(writer, command, resources[0..resource_count]);
    const pixels = try writer.need(frame.pixels.len);
    @memcpy(pixels, frame.pixels);
}

fn collectFrameResources(
    commands: []const canvas.Command,
    output: *[maximum_frame_resources]canvas.FrameResourceView,
) !usize {
    var used: usize = 0;
    for (commands) |command| {
        const view: ?canvas.FrameResourceView = switch (command) {
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
    resource: canvas.FrameResourceView,
    frame: canvas.Composer.Frame,
) !void {
    var upload: ?canvas.FrameResourceUpload = null;
    for (frame.uploads) |candidate| {
        if (std.meta.eql(candidate.resource, resource.resource)) {
            upload = candidate;
            break;
        }
    }
    try writer.writeU64(@backingInt(resource.resource.source));
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

fn writeCommand(
    writer: *Writer,
    command: canvas.Command,
    resources: []const canvas.FrameResourceView,
) !void {
    switch (command) {
        .solid => |value| {
            try writer.writeU8(0);
            try writer.writeU8(0xff);
            try writer.writeU8(0);
            try writer.writeU8(0);
            try writer.writeU32(colorBits(value.color));
            try writeRect(writer, value.rect);
            try writeRect(writer, value.rect);
            try writer.zeroes(8);
        },
        .alpha_mask => |value| {
            try writer.writeU8(1);
            try writer.writeU8(try frameResourceIndex(resources, value.resource.resource));
            try writer.writeU8(if (value.cursor_component) 1 else 0);
            try writer.writeU8(0);
            try writer.writeU32(colorBits(value.color));
            try writeRect(writer, value.destination);
            try writeRect(writer, value.clip);
            try writeSourceRect(writer, value.resource);
        },
        .rgba => |value| {
            try writer.writeU8(2);
            try writer.writeU8(try frameResourceIndex(resources, value.resource.resource));
            try writer.writeU8(0);
            try writer.writeU8(0);
            try writer.writeU32(0);
            try writeRect(writer, value.destination);
            try writeRect(writer, value.clip);
            try writeSourceRect(writer, value.resource);
        },
    }
}

fn frameResourceIndex(
    resources: []const canvas.FrameResourceView,
    resource: canvas.FrameResourceRef,
) !u8 {
    for (resources, 0..) |candidate, index| {
        if (std.meta.eql(candidate.resource, resource)) return @intCast(index);
    }
    return error.MissingResource;
}

fn writeRect(writer: *Writer, rect: canvas.Rect) !void {
    try writer.writeI32(rect.x);
    try writer.writeI32(rect.y);
    try writer.writeU16(rect.width);
    try writer.writeU16(rect.height);
}

fn writeSourceRect(writer: *Writer, resource: canvas.FrameResourceView) !void {
    const source = resource.source orelse canvas.SourceRect{
        .x = 0,
        .y = 0,
        .width = resource.size.width,
        .height = resource.size.height,
    };
    try writer.writeU16(source.x);
    try writer.writeU16(source.y);
    try writer.writeU16(source.width);
    try writer.writeU16(source.height);
}

fn colorBits(value: canvas.Color) u32 {
    return @bitCast(value);
}

fn checkedMul(left: usize, right: usize) HostPacketError!usize {
    return std.math.mul(usize, left, right) catch error.IntegerOverflow;
}

fn checkedAdd(left: usize, right: usize) HostPacketError!usize {
    return std.math.add(usize, left, right) catch error.IntegerOverflow;
}
