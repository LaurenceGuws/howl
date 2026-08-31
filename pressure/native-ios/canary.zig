const std = @import("std");
const client = @import("howl_client");
const text = @import("howl_text");
const canvas = @import("canvas");
const terminal = @import("terminal");

const rows_count: usize = 36;
const columns_count: usize = 51;
const cell_count: usize = rows_count * columns_count;
const global_header_bytes: usize = 32;
const frame_header_bytes: usize = 48;
const resource_record_bytes: usize = 48;
const removal_record_bytes: usize = 24;
const command_record_bytes: usize = 40;
const maximum_frame_resources: usize = 8;

const style_dim: u16 = 1 << 1;
const style_reverse: u16 = 1 << 5;
const style_invisible: u16 = 1 << 6;
const style_underline: u16 = 1 << 7;
const style_strike: u16 = 1 << 8;

const PressureError = error{
    BufferTooSmall,
    FixtureOverflow,
    ResourceLimit,
    MissingResource,
    InvalidFrame,
    IntegerOverflow,
};

const CellPaint = struct {
    style_bits: u16 = 0,
    foreground: client.view.TextColor = .{ .kind = .default, .value = 0 },
    background: client.view.TextColor = .{ .kind = .default, .value = 0 },
    underline: client.view.TextColor = .{ .kind = .default, .value = 0 },
    underline_style: u8 = 0,
};

const Fixture = struct {
    rows: []client.rich.Row,
    cells: []client.rich.Cell,
    scalars: []u32,
    scalar_used: usize,

    fn init(allocator: std.mem.Allocator) !Fixture {
        const rows = try allocator.alloc(client.rich.Row, rows_count);
        errdefer allocator.free(rows);
        const cells = try allocator.alloc(client.rich.Cell, cell_count);
        errdefer allocator.free(cells);
        const scalars = try allocator.alloc(u32, 512);
        errdefer allocator.free(scalars);

        for (rows, 0..) |*row, index| {
            const first = index * columns_count;
            row.* = .{
                .wrapped = false,
                .line_geometry = 0,
                .cells = cells[first .. first + columns_count],
            };
        }
        for (cells) |*value| value.* = blankCell();

        return .{
            .rows = rows,
            .cells = cells,
            .scalars = scalars,
            .scalar_used = 0,
        };
    }

    fn deinit(self: *Fixture, allocator: std.mem.Allocator) void {
        allocator.free(self.scalars);
        allocator.free(self.cells);
        allocator.free(self.rows);
        self.* = undefined;
    }

    fn cell(self: *Fixture, row: usize, column: usize) !*client.rich.Cell {
        if (row >= rows_count or column >= columns_count) return error.FixtureOverflow;
        return &self.cells[row * columns_count + column];
    }

    fn putScalars(
        self: *Fixture,
        row: usize,
        column: usize,
        values: []const u32,
        width: u8,
        paint: CellPaint,
    ) !usize {
        if (values.len == 0 or values.len > 16)
            return error.FixtureOverflow;
        if (width == 0 or column + width > columns_count) return error.FixtureOverflow;
        if (values.len > self.scalars.len - self.scalar_used) return error.FixtureOverflow;

        const first = self.scalar_used;
        @memcpy(self.scalars[first .. first + values.len], values);
        self.scalar_used += values.len;
        const lead = try self.cell(row, column);
        lead.* = paintedCell(self.scalars[first .. first + values.len], width, 0, paint);
        if (width > 1) {
            for (1..width) |x| {
                const continuation = try self.cell(row, column + x);
                continuation.* = paintedCell(&.{}, width, @intCast(x), paint);
            }
        }
        return column + width;
    }

    fn putAscii(
        self: *Fixture,
        row: usize,
        start_column: usize,
        bytes: []const u8,
        paint: CellPaint,
    ) !usize {
        var column = start_column;
        for (bytes) |byte| {
            if (byte > 0x7f) return error.FixtureOverflow;
            const one = [_]u32{byte};
            column = try self.putScalars(row, column, &one, 1, paint);
        }
        return column;
    }
};

const Writer = struct {
    bytes: []u8,
    offset: usize = 0,

    fn need(self: *Writer, count: usize) PressureError![]u8 {
        if (count > self.bytes.len -| self.offset) return error.BufferTooSmall;
        const result = self.bytes[self.offset .. self.offset + count];
        self.offset += count;
        return result;
    }

    fn zeroes(self: *Writer, count: usize) PressureError!void {
        @memset(try self.need(count), 0);
    }

    fn writeU8(self: *Writer, value: u8) PressureError!void {
        (try self.need(1))[0] = value;
    }

    fn writeU16(self: *Writer, value: u16) PressureError!void {
        const output: *[2]u8 = @ptrCast((try self.need(2)).ptr);
        std.mem.writeInt(u16, output, value, .little);
    }

    fn writeU32(self: *Writer, value: u32) PressureError!void {
        const output: *[4]u8 = @ptrCast((try self.need(4)).ptr);
        std.mem.writeInt(u32, output, value, .little);
    }

    fn writeI32(self: *Writer, value: i32) PressureError!void {
        const output: *[4]u8 = @ptrCast((try self.need(4)).ptr);
        std.mem.writeInt(i32, output, value, .little);
    }

    fn writeU64(self: *Writer, value: u64) PressureError!void {
        const output: *[8]u8 = @ptrCast((try self.need(8)).ptr);
        std.mem.writeInt(u64, output, value, .little);
    }
};

pub export fn howl_ios_native_canary_version() u32 {
    return 2;
}

pub export fn howl_ios_native_canary_init(
    primary_ptr: [*]const u8,
    primary_len: usize,
    fallback_ptr: [*]const u8,
    fallback_len: usize,
) i32 {
    if (primary_len == 0 or fallback_len == 0) return 1;
    const allocator = std.heap.c_allocator;
    const fallbacks = [_][]const u8{fallback_ptr[0..fallback_len]};
    const fonts = text.FontSet.init(allocator, .{
        .primary = primary_ptr[0..primary_len],
        .fallbacks = &fallbacks,
        .size = .{ .pixels = 16 },
    }) catch return 2;
    defer fonts.deinit();

    const content = terminal.initContent(allocator, fonts, contentConfig()) catch return 3;
    defer terminal.deinitContent(content);

    const usage = terminal.contentUsage(content);
    if (usage.producer_revision != 0 or usage.resource_generation != 0) return 4;
    return 0;
}

/// Pressure-only synchronous final-Canvas canary.
///
/// The caller owns `output` and retains no native pointer. On success the prefix
/// `[0..output_len.*]` is one private HCR1 corpus containing a quality frame and
/// an unchanged sparse-residency frame generated by current Howl source.
pub export fn howl_ios_native_render_hcr1(
    primary_ptr: [*]const u8,
    primary_len: usize,
    fallback_ptr: [*]const u8,
    fallback_len: usize,
    output_ptr: [*]u8,
    output_capacity: usize,
    output_len: *usize,
) i32 {
    output_len.* = 0;
    if (primary_len == 0 or fallback_len == 0 or output_capacity == 0) return 1;
    const written = renderHcr1(
        primary_ptr[0..primary_len],
        fallback_ptr[0..fallback_len],
        output_ptr[0..output_capacity],
    ) catch |failure| return switch (failure) {
        error.BufferTooSmall => 6,
        else => 5,
    };
    output_len.* = written;
    return 0;
}

fn renderHcr1(primary: []const u8, fallback: []const u8, output: []u8) !usize {
    const allocator = std.heap.c_allocator;
    const fallbacks = [_][]const u8{fallback};
    const fonts = try text.FontSet.init(allocator, .{
        .primary = primary,
        .fallbacks = &fallbacks,
        .size = .{ .pixels = 16 },
    });
    defer fonts.deinit();

    var fixture = try Fixture.init(allocator);
    defer fixture.deinit(allocator);
    try populateFixture(&fixture);
    var palette: [256]client.rich.Rgba = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff });
    palette[1] = .{ .r = 205, .g = 49, .b = 49, .a = 0xff };
    palette[4] = .{ .r = 36, .g = 114, .b = 200, .a = 0xff };
    var links: [0]client.rich.Hyperlink = .{};
    const source = client.rich.Snapshot{
        .allocator = allocator,
        .begin = .{
            .revision = 1,
            .terminal_revision = 1,
            .format = .text_v1,
            .history_offset = 0,
            .history_count = 0,
            .history_row_base = 0,
            .rows = rows_count,
            .columns = columns_count,
            .cursor_row = 4,
            .cursor_column = 8,
            .cursor_shape = 0,
            .cursor_visible = true,
            .cursor_blink = false,
            .alternate_screen = false,
            .stream_closed = false,
            .child_exited = false,
            .leader_present = true,
            .you_are_leader = false,
        },
        .presentation = .{
            .cursor_age_ns = null,
            .presence_bits = 0,
            .flags = 0,
            .reverse_screen = false,
            .palette = palette,
            .foreground = .{ .r = 220, .g = 220, .b = 220, .a = 0xff },
            .background = .{ .r = 24, .g = 25, .b = 33, .a = 0xff },
            .cursor = null,
            .cursor_text = null,
            .selection_background = null,
            .selection_foreground = null,
        },
        .rows = fixture.rows,
        .hyperlinks = links[0..],
    };

    const view = try client.view.project(allocator, &source);
    defer client.view.deinit(view);
    const content = try terminal.initContent(allocator, fonts, contentConfig());
    defer terminal.deinitContent(content);
    var composer = try canvas.Composer.init(allocator, .{
        .sources = 1,
        .retained_resources = 4,
        .retained_commands = 4096,
        .retained_pixel_bytes = 32 * 1024,
        .composition_sources = 1,
        .candidate_resources = 4,
        .candidate_commands = 4096,
        .candidate_pixel_bytes = 32 * 1024,
    });
    defer composer.deinit();
    const source_id = try composer.registerSource();
    const cursor = terminal.CursorContext{
        .pane = 1,
        .source = source_id,
        .visible_set_revision = 1,
        .lifecycle_revision = 1,
    };
    const update1 = try terminal.takeContentUpdate(content, view, cursor);
    try composer.apply(source_id, update1);
    const placement = canvas.Composer.Placement{
        .source = source_id,
        .origin = .{ .x = 0, .y = 0 },
        .clip = .{ .x = 0, .y = 0, .width = 510, .height = 720 },
    };
    try composer.setComposition(.{
        .surface = .{ .width = 510, .height = 720 },
        .sources = &.{placement},
        .focused_source = source_id,
    });

    const frame_uploads = try allocator.alloc(canvas.FrameResourceUpload, 8);
    defer allocator.free(frame_uploads);
    const frame_removals = try allocator.alloc(canvas.FrameResourceRef, 8);
    defer allocator.free(frame_removals);
    const frame_commands = try allocator.alloc(canvas.Command, 4096);
    defer allocator.free(frame_commands);
    const frame_pixels = try allocator.alloc(u8, 32 * 1024);
    defer allocator.free(frame_pixels);

    var writer = Writer{ .bytes = output };
    try writeGlobalHeader(&writer);
    const frame1 = try composer.frame(&.{}, .{
        .uploads = frame_uploads,
        .removals = frame_removals,
        .commands = frame_commands,
        .pixels = frame_pixels,
    });
    try writeFrame(&writer, frame1, 1);

    var residency: [maximum_frame_resources]canvas.Residency = undefined;
    if (frame1.uploads.len > residency.len) return error.ResourceLimit;
    for (frame1.uploads, 0..) |upload, index| {
        residency[index] = .{
            .resource = upload.resource,
            .format = upload.format,
            .size = upload.size,
        };
    }

    const update2 = try terminal.takeContentUpdate(content, view, cursor);
    try composer.apply(source_id, update2);
    const frame2 = try composer.frame(residency[0..frame1.uploads.len], .{
        .uploads = frame_uploads,
        .removals = frame_removals,
        .commands = frame_commands,
        .pixels = frame_pixels,
    });
    if (frame2.uploads.len != 0) return error.InvalidFrame;
    try writeFrame(&writer, frame2, 2);
    return writer.offset;
}

fn contentConfig() terminal.ContentConfig {
    return .{
        .cell_size = .{ .width = 10, .height = 20 },
        .shape_cache = .{
            .entry_capacity = 128,
            .scalar_capacity = 512,
            .glyph_capacity = 512,
            .max_sequence_scalars = 16,
        },
        .atlas = .{
            .width = 128,
            .height = 128,
            .entry_capacity = 256,
        },
        .shaped_capacity = 32,
        .raster_bytes = 16 * 1024,
        .command_capacity = 4096,
    };
}

fn blankCell() client.rich.Cell {
    return paintedCell(&.{}, 1, 0, .{});
}

fn paintedCell(
    scalars: []const u32,
    width: u8,
    x: u8,
    paint: CellPaint,
) client.rich.Cell {
    return .{
        .scalars = scalars,
        .width = width,
        .height = 1,
        .x = x,
        .y = 0,
        .subscale_n = 1,
        .subscale_d = 1,
        .vertical_align = 0,
        .horizontal_align = 0,
        .semantic_width = width > 1,
        .font = 0,
        .baseline = 0,
        .underline_style = paint.underline_style,
        .protection = 0,
        .style_bits = paint.style_bits,
        .foreground = paint.foreground,
        .background = paint.background,
        .underline_color = paint.underline,
        .link_id = 0,
    };
}

fn populateFixture(fixture: *Fixture) !void {
    var column = try fixture.putAscii(0, 0, "HOWL_NATIVE_IOS ", .{ .foreground = .{ .kind = .indexed, .value = 1 } });
    const lambda = [_]u32{0x03bb};
    column = try fixture.putScalars(0, column, &lambda, 1, .{});
    column = try fixture.putAscii(0, column, " ", .{});
    const beta = [_]u32{0x03b2};
    column = try fixture.putScalars(0, column, &beta, 1, .{});
    column = try fixture.putAscii(0, column, " ", .{});
    const combined = [_]u32{ 'e', 0x0301 };
    column = try fixture.putScalars(0, column, &combined, 1, .{});
    column = try fixture.putAscii(0, column, " ", .{});
    const box = [_]u32{0x2500};
    column = try fixture.putScalars(0, column, &box, 1, .{});
    column = try fixture.putAscii(0, column, " ", .{});
    const nerd = [_]u32{0xe0b0};
    column = try fixture.putScalars(0, column, &nerd, 1, .{});
    column = try fixture.putAscii(0, column, " ", .{});
    const watch = [_]u32{0x231a};
    _ = try fixture.putScalars(0, column, &watch, 2, .{});

    column = try fixture.putAscii(1, 0, "DIM", .{ .style_bits = style_dim });
    column = try fixture.putAscii(1, column, " ", .{});
    column = try fixture.putAscii(1, column, "REVERSE", .{ .style_bits = style_reverse });
    column = try fixture.putAscii(1, column, " ", .{});
    column = try fixture.putAscii(1, column, "UNDER", .{
        .style_bits = style_underline,
        .underline_style = 1,
    });
    column = try fixture.putAscii(1, column, " ", .{});
    column = try fixture.putAscii(1, column, "STRIKE", .{ .style_bits = style_strike });
    column = try fixture.putAscii(1, column, " ", .{});
    column = try fixture.putAscii(1, column, "BLUEBG", .{ .background = .{ .kind = .indexed, .value = 4 } });
    column = try fixture.putAscii(1, column, " ", .{});
    _ = try fixture.putAscii(1, column, "RGBBG", .{ .background = .{ .kind = .rgb, .value = 0x0a141e } });

    column = try fixture.putAscii(2, 0, "DOUBLE", .{
        .style_bits = style_underline,
        .underline_style = 1,
    });
    column = try fixture.putAscii(2, column, " ", .{});
    column = try fixture.putAscii(2, column, "WAVY", .{
        .style_bits = style_underline,
        .underline_style = 2,
    });
    column = try fixture.putAscii(2, column, " ", .{});
    column = try fixture.putAscii(2, column, "DOTTED", .{
        .style_bits = style_underline,
        .underline_style = 3,
    });
    column = try fixture.putAscii(2, column, " ", .{});
    _ = try fixture.putAscii(2, column, "DASHED", .{
        .style_bits = style_underline,
        .underline_style = 4,
    });

    _ = try fixture.putAscii(4, 0, "sh-5.3$", .{});
    _ = style_invisible;
}

fn writeGlobalHeader(writer: *Writer) !void {
    const magic = try writer.need(4);
    @memcpy(magic, "HCR1");
    try writer.writeU16(1);
    try writer.writeU16(global_header_bytes);
    try writer.writeU32(2);
    try writer.writeU32(1);
    try writer.writeU16(510);
    try writer.writeU16(720);
    try writer.zeroes(global_header_bytes - 20);
}

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

fn checkedMul(left: usize, right: usize) PressureError!usize {
    return std.math.mul(usize, left, right) catch error.IntegerOverflow;
}

fn checkedAdd(left: usize, right: usize) PressureError!usize {
    return std.math.add(usize, left, right) catch error.IntegerOverflow;
}
