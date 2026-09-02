//! Coarse immutable native snapshot view for UI and other presentation clients.
//!
//! This module never parses `text_v1`. It projects the one accepted rich model
//! into one explicitly owned allocation and exposes only batched semantic slices.
//! The backing layout is private and is not a C/FFI ABI.

const std = @import("std");
const protocol = @import("howl_session").protocol;
const rich = @import("rich.zig");

pub const Error = std.mem.Allocator.Error || error{
    InvalidRichSnapshot,
    ViewTooLarge,
};

pub const Begin = protocol.SnapshotBegin;
pub const Presentation = rich.Presentation;
pub const TextColor = protocol.TextColor;

/// Opaque owner of one immutable projected revision.
pub const Snapshot = opaque {};

pub const Row = struct {
    cell_offset: u32,
    cell_count: u32,
    wrapped: bool,
    line_geometry: u8,
};

pub const Cell = struct {
    scalar_offset: u32,
    scalar_count: u8,
    width: u8,
    height: u8,
    x: u8,
    y: u8,
    subscale_n: u8,
    subscale_d: u8,
    vertical_align: u8,
    horizontal_align: u8,
    semantic_width: bool,
    font: u8,
    baseline: u8,
    underline_style: u8,
    protection: u8,
    style_bits: u16,
    foreground: TextColor,
    background: TextColor,
    underline_color: TextColor,
    link_id: u32,
};

pub const Hyperlink = struct {
    link_id: u32,
    uri_offset: u32,
    uri_len: u32,
};

const maximum_view_bytes = protocol.maximum_snapshot_bytes * 2;

const Impl = struct {
    allocator: std.mem.Allocator,
    word_count: usize,
    total_bytes: usize,
    rows_offset: usize,
    cells_offset: usize,
    scalars_offset: usize,
    hyperlinks_offset: usize,
    uris_offset: usize,
    row_count: usize,
    cell_count: usize,
    scalar_count: usize,
    hyperlink_count: usize,
    uri_bytes: usize,
    begin: Begin,
    presentation: Presentation,
};

comptime {
    if (@alignOf(Impl) > @alignOf(u128)) @compileError("view owner alignment exceeds backing allocation");

    // `rich.receive` already caps the complete framed snapshot at 4 MiB. Prove
    // that every coarse fixed record costs at most twice its corresponding
    // frozen wire record. Scalar and URI payload bytes retain their native byte
    // width. The fixed owner plus worst section-alignment padding must likewise
    // fit inside twice the snapshot begin/presentation/end wire overhead. These
    // assertions make the 8 MiB view ceiling mechanically follow the wire cap.
    const row_wire_fixed = protocol.header_bytes +
        protocol.text_v1.record_header_bytes + protocol.text_v1.row_header_bytes;
    const hyperlink_wire_fixed = protocol.header_bytes +
        protocol.text_v1.record_header_bytes + protocol.text_v1.hyperlink_header_bytes;
    const fixed_wire = protocol.header_bytes + protocol.payload_bytes.snapshot_begin +
        protocol.header_bytes + protocol.text_v1.record_header_bytes + protocol.text_v1.presentation_bytes +
        protocol.header_bytes + protocol.payload_bytes.snapshot_end;
    const fixed_view = @sizeOf(Impl) +
        (@alignOf(Row) - 1) + (@alignOf(Cell) - 1) +
        (@alignOf(u32) - 1) + (@alignOf(Hyperlink) - 1);

    if (@sizeOf(Row) > row_wire_fixed * 2) @compileError("coarse row exceeds 2x wire bound");
    if (@sizeOf(Cell) > protocol.text_v1.cell_header_bytes * 2) @compileError("coarse cell exceeds 2x wire bound");
    if (@sizeOf(u32) != 4) @compileError("coarse scalar no longer matches text_v1 scalar width");
    if (@sizeOf(Hyperlink) > hyperlink_wire_fixed * 2) @compileError("coarse hyperlink exceeds 2x wire bound");
    if (fixed_view > fixed_wire * 2) @compileError("coarse fixed owner exceeds 2x wire bound");
}

/// Projects one already-decoded rich snapshot into one immutable allocation.
///
/// The caller owns the returned view and must call `deinit`. The source may be
/// released immediately after this returns.
pub fn project(allocator: std.mem.Allocator, source: *const rich.Snapshot) Error!*Snapshot {
    const counts = try validateAndCount(source);

    const rows_offset = alignAfter(Row, @sizeOf(Impl));
    const rows_end = try sectionEnd(Row, rows_offset, source.rows.len);
    const cells_offset = alignAfter(Cell, rows_end);
    const cells_end = try sectionEnd(Cell, cells_offset, counts.cells);
    const scalars_offset = alignAfter(u32, cells_end);
    const scalars_end = try sectionEnd(u32, scalars_offset, counts.scalars);
    const hyperlinks_offset = alignAfter(Hyperlink, scalars_end);
    const hyperlinks_end = try sectionEnd(Hyperlink, hyperlinks_offset, source.hyperlinks.len);
    const uris_offset = hyperlinks_end;
    const total_bytes = std.math.add(usize, uris_offset, counts.uri_bytes) catch
        return error.ViewTooLarge;
    if (total_bytes > maximum_view_bytes) return error.ViewTooLarge;

    const word_count = std.math.divCeil(usize, total_bytes, @sizeOf(u128)) catch unreachable;
    const storage = try allocator.alloc(u128, word_count);
    errdefer allocator.free(storage);
    const bytes = std.mem.sliceAsBytes(storage);
    @memset(bytes, 0);

    const impl: *Impl = @ptrCast(storage.ptr);
    impl.* = .{
        .allocator = allocator,
        .word_count = word_count,
        .total_bytes = total_bytes,
        .rows_offset = rows_offset,
        .cells_offset = cells_offset,
        .scalars_offset = scalars_offset,
        .hyperlinks_offset = hyperlinks_offset,
        .uris_offset = uris_offset,
        .row_count = source.rows.len,
        .cell_count = counts.cells,
        .scalar_count = counts.scalars,
        .hyperlink_count = source.hyperlinks.len,
        .uri_bytes = counts.uri_bytes,
        .begin = source.begin,
        .presentation = source.presentation,
    };

    const output_rows = mutableSliceAt(Row, bytes, rows_offset, source.rows.len);
    const output_cells = mutableSliceAt(Cell, bytes, cells_offset, counts.cells);
    const output_scalars = mutableSliceAt(u32, bytes, scalars_offset, counts.scalars);
    const output_links = mutableSliceAt(Hyperlink, bytes, hyperlinks_offset, source.hyperlinks.len);
    const output_uris = bytes[uris_offset .. uris_offset + counts.uri_bytes];

    var cell_index: usize = 0;
    var scalar_index: usize = 0;
    for (source.rows, 0..) |source_row, row_index| {
        output_rows[row_index] = .{
            .cell_offset = @intCast(cell_index),
            .cell_count = @intCast(source_row.cells.len),
            .wrapped = source_row.wrapped,
            .line_geometry = source_row.line_geometry,
        };
        for (source_row.cells) |source_cell| {
            output_cells[cell_index] = .{
                .scalar_offset = @intCast(scalar_index),
                .scalar_count = @intCast(source_cell.scalars.len),
                .width = source_cell.width,
                .height = source_cell.height,
                .x = source_cell.x,
                .y = source_cell.y,
                .subscale_n = source_cell.subscale_n,
                .subscale_d = source_cell.subscale_d,
                .vertical_align = source_cell.vertical_align,
                .horizontal_align = source_cell.horizontal_align,
                .semantic_width = source_cell.semantic_width,
                .font = source_cell.font,
                .baseline = source_cell.baseline,
                .underline_style = source_cell.underline_style,
                .protection = source_cell.protection,
                .style_bits = source_cell.style_bits,
                .foreground = source_cell.foreground,
                .background = source_cell.background,
                .underline_color = source_cell.underline_color,
                .link_id = source_cell.link_id,
            };
            @memcpy(
                output_scalars[scalar_index .. scalar_index + source_cell.scalars.len],
                source_cell.scalars,
            );
            scalar_index += source_cell.scalars.len;
            cell_index += 1;
        }
    }

    var uri_index: usize = 0;
    for (source.hyperlinks, 0..) |source_link, link_index| {
        output_links[link_index] = .{
            .link_id = source_link.link_id,
            .uri_offset = @intCast(uri_index),
            .uri_len = @intCast(source_link.uri_bytes.len),
        };
        @memcpy(output_uris[uri_index .. uri_index + source_link.uri_bytes.len], source_link.uri_bytes);
        uri_index += source_link.uri_bytes.len;
    }

    return @ptrCast(impl);
}

/// Releases one view. Every slice previously borrowed from it becomes invalid.
pub fn deinit(snapshot: *Snapshot) void {
    const impl = mutableImpl(snapshot);
    const allocator = impl.allocator;
    const word_count = impl.word_count;
    const storage: [*]u128 = @ptrCast(@alignCast(impl));
    allocator.free(storage[0..word_count]);
}

pub fn begin(snapshot: *const Snapshot) *const Begin {
    return &constImpl(snapshot).begin;
}

pub fn presentation(snapshot: *const Snapshot) *const Presentation {
    return &constImpl(snapshot).presentation;
}

pub fn rows(snapshot: *const Snapshot) []const Row {
    const impl = constImpl(snapshot);
    return constSliceAt(Row, ownerBytes(impl), impl.rows_offset, impl.row_count);
}

pub fn cells(snapshot: *const Snapshot) []const Cell {
    const impl = constImpl(snapshot);
    return constSliceAt(Cell, ownerBytes(impl), impl.cells_offset, impl.cell_count);
}

pub fn scalars(snapshot: *const Snapshot) []const u32 {
    const impl = constImpl(snapshot);
    return constSliceAt(u32, ownerBytes(impl), impl.scalars_offset, impl.scalar_count);
}

pub fn hyperlinks(snapshot: *const Snapshot) []const Hyperlink {
    const impl = constImpl(snapshot);
    return constSliceAt(Hyperlink, ownerBytes(impl), impl.hyperlinks_offset, impl.hyperlink_count);
}

pub fn uris(snapshot: *const Snapshot) []const u8 {
    const impl = constImpl(snapshot);
    return ownerBytes(impl)[impl.uris_offset .. impl.uris_offset + impl.uri_bytes];
}

const Counts = struct {
    cells: usize,
    scalars: usize,
    uri_bytes: usize,
};

fn validateAndCount(source: *const rich.Snapshot) Error!Counts {
    if (source.rows.len != source.begin.rows) {
        return error.InvalidRichSnapshot;
    }
    if (!validPresentation(source.presentation) or
        source.hyperlinks.len > protocol.text_v1.maximum_hyperlinks)
    {
        return error.InvalidRichSnapshot;
    }

    var referenced: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var resolved: [protocol.text_v1.maximum_hyperlinks + 1]bool = @splat(false);
    var cell_count: usize = 0;
    var scalar_count: usize = 0;
    for (source.rows) |row| {
        if (row.cells.len != source.begin.columns or row.line_geometry > 3) {
            return error.InvalidRichSnapshot;
        }
        cell_count = std.math.add(usize, cell_count, row.cells.len) catch return error.ViewTooLarge;
        for (row.cells) |cell| {
            if (!validCell(cell)) return error.InvalidRichSnapshot;
            if (cell.link_id != 0) referenced[cell.link_id] = true;
            scalar_count = std.math.add(usize, scalar_count, cell.scalars.len) catch
                return error.ViewTooLarge;
        }
    }

    var uri_bytes: usize = 0;
    for (source.hyperlinks) |link| {
        if (link.link_id == 0 or
            link.link_id > protocol.text_v1.maximum_hyperlinks or
            link.uri_bytes.len == 0 or
            link.uri_bytes.len > protocol.text_v1.maximum_hyperlink_uri_bytes or
            !referenced[link.link_id] or resolved[link.link_id])
        {
            return error.InvalidRichSnapshot;
        }
        resolved[link.link_id] = true;
        uri_bytes = std.math.add(usize, uri_bytes, link.uri_bytes.len) catch
            return error.ViewTooLarge;
    }
    for (referenced[1..], resolved[1..]) |needed, seen| {
        if (needed != seen) return error.InvalidRichSnapshot;
    }

    if (cell_count > std.math.maxInt(u32) or
        scalar_count > std.math.maxInt(u32) or
        uri_bytes > std.math.maxInt(u32))
    {
        return error.ViewTooLarge;
    }
    return .{ .cells = cell_count, .scalars = scalar_count, .uri_bytes = uri_bytes };
}

fn validPresentation(value: Presentation) bool {
    if (value.presence_bits & ~protocol.text_v1.presentation_presence.known != 0 or
        value.flags & ~protocol.text_v1.presentation_flags.known != 0 or
        value.reverse_screen != (value.flags & protocol.text_v1.presentation_flags.reverse_screen != 0))
    {
        return false;
    }
    return optionalPresence(value.cursor, value.presence_bits, protocol.text_v1.presentation_presence.cursor) and
        optionalPresence(value.cursor_text, value.presence_bits, protocol.text_v1.presentation_presence.cursor_text) and
        optionalPresence(value.selection_background, value.presence_bits, protocol.text_v1.presentation_presence.selection_background) and
        optionalPresence(value.selection_foreground, value.presence_bits, protocol.text_v1.presentation_presence.selection_foreground);
}

fn optionalPresence(value: ?rich.Rgba, bits: u8, bit: u8) bool {
    return (value != null) == (bits & bit != 0);
}

fn validCell(cell: rich.Cell) bool {
    if (cell.scalars.len > protocol.text_v1.maximum_cell_scalars or
        cell.width == 0 or cell.height == 0 or cell.x >= cell.width or cell.y >= cell.height or
        cell.subscale_n > 15 or cell.subscale_d > 15 or
        cell.vertical_align > 3 or cell.horizontal_align > 3 or
        cell.font > 15 or cell.baseline > 2 or cell.underline_style > 4 or cell.protection > 2 or
        cell.style_bits & ~protocol.text_v1.style.known != 0 or
        cell.link_id > protocol.text_v1.maximum_hyperlinks or
        (cell.x != 0 or cell.y != 0) and cell.scalars.len != 0 or
        !validColor(cell.foreground) or !validColor(cell.background) or !validColor(cell.underline_color))
    {
        return false;
    }
    for (cell.scalars) |scalar| {
        if (scalar > 0x10ffff or scalar >= 0xd800 and scalar <= 0xdfff) return false;
    }
    return true;
}

fn validColor(value: TextColor) bool {
    var encoded: [protocol.text_v1.color_bytes]u8 = undefined;
    protocol.encodeTextColor(&encoded, value) catch return false;
    return true;
}

fn alignAfter(comptime T: type, previous: usize) usize {
    return std.mem.alignForward(usize, previous, @alignOf(T));
}

fn sectionEnd(comptime T: type, offset: usize, count: usize) Error!usize {
    const bytes = std.math.mul(usize, @sizeOf(T), count) catch return error.ViewTooLarge;
    return std.math.add(usize, offset, bytes) catch return error.ViewTooLarge;
}

fn mutableSliceAt(comptime T: type, bytes: []u8, offset: usize, count: usize) []T {
    const end = offset + @sizeOf(T) * count;
    const aligned: []align(@alignOf(T)) u8 = @alignCast(bytes[offset..end]);
    return std.mem.bytesAsSlice(T, aligned);
}

fn constSliceAt(comptime T: type, bytes: []const u8, offset: usize, count: usize) []const T {
    const end = offset + @sizeOf(T) * count;
    const aligned: []align(@alignOf(T)) const u8 = @alignCast(bytes[offset..end]);
    return std.mem.bytesAsSlice(T, aligned);
}

fn constImpl(snapshot: *const Snapshot) *const Impl {
    return @ptrCast(@alignCast(snapshot));
}

fn mutableImpl(snapshot: *Snapshot) *Impl {
    return @ptrCast(@alignCast(snapshot));
}

fn ownerBytes(impl: *const Impl) []const u8 {
    const base: [*]const u8 = @ptrCast(impl);
    return base[0..impl.total_bytes];
}

fn testBegin(rows_count: u16, columns_count: u16) Begin {
    return .{
        .revision = 1,
        .terminal_revision = 1,
        .history_offset = 0,
        .history_count = 0,
        .history_row_base = 0,
        .rows = rows_count,
        .columns = columns_count,
        .cursor_row = 0,
        .cursor_column = 0,
        .cursor_shape = 0,
        .cursor_visible = false,
        .cursor_blink = false,
        .alternate_screen = false,
        .stream_closed = false,
        .child_exited = false,
        .leader_present = false,
        .you_are_leader = false,
    };
}

fn testPresentation(palette: [256]rich.Rgba) Presentation {
    return .{
        .cursor_age_ns = null,
        .presence_bits = 0,
        .flags = 0,
        .reverse_screen = false,
        .palette = palette,
        .foreground = .{ .r = 0, .g = 0, .b = 0, .a = 0xff },
        .background = .{ .r = 0, .g = 0, .b = 0, .a = 0xff },
        .cursor = null,
        .cursor_text = null,
        .selection_background = null,
        .selection_foreground = null,
    };
}

test "coarse view preserves rich semantics in one allocation" {
    var first_scalars = [_]u32{ 'e', 0x0301 };
    var cells_source = [_]rich.Cell{
        .{
            .scalars = first_scalars[0..],
            .width = 1,
            .height = 1,
            .x = 0,
            .y = 0,
            .subscale_n = 1,
            .subscale_d = 1,
            .vertical_align = 0,
            .horizontal_align = 0,
            .semantic_width = false,
            .font = 0,
            .baseline = 0,
            .underline_style = 2,
            .protection = 0,
            .style_bits = protocol.text_v1.style.bold | protocol.text_v1.style.underline,
            .foreground = .{ .kind = .rgb, .value = 0x112233 },
            .background = .{ .kind = .indexed, .value = 4 },
            .underline_color = .{ .kind = .rgb, .value = 0x445566 },
            .link_id = 7,
        },
        .{
            .scalars = &.{},
            .width = 1,
            .height = 1,
            .x = 0,
            .y = 0,
            .subscale_n = 1,
            .subscale_d = 1,
            .vertical_align = 0,
            .horizontal_align = 0,
            .semantic_width = true,
            .font = 1,
            .baseline = 1,
            .underline_style = 0,
            .protection = 1,
            .style_bits = 0,
            .foreground = .{ .kind = .default, .value = 0 },
            .background = .{ .kind = .default, .value = 0 },
            .underline_color = .{ .kind = .default, .value = 0 },
            .link_id = 0,
        },
    };
    var rows_source = [_]rich.Row{.{
        .wrapped = true,
        .line_geometry = 2,
        .cells = cells_source[0..],
    }};
    var uri = [_]u8{ 'A', 0, 0xff, 'Z' };
    var links_source = [_]rich.Hyperlink{.{ .link_id = 7, .uri_bytes = uri[0..] }};
    var palette: [256]rich.Rgba = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff });
    palette[4] = .{ .r = 1, .g = 2, .b = 3, .a = 0xff };
    const source = rich.Snapshot{
        .allocator = std.testing.allocator,
        .begin = .{
            .revision = 11,
            .terminal_revision = 9,
            .history_offset = 3,
            .history_count = 8,
            .history_row_base = 2,
            .rows = 1,
            .columns = 2,
            .cursor_row = 0,
            .cursor_column = 1,
            .cursor_shape = 2,
            .cursor_visible = true,
            .cursor_blink = false,
            .alternate_screen = false,
            .stream_closed = false,
            .child_exited = false,
            .leader_present = true,
            .you_are_leader = false,
        },
        .presentation = .{
            .cursor_age_ns = 123,
            .presence_bits = protocol.text_v1.presentation_presence.cursor,
            .flags = protocol.text_v1.presentation_flags.reverse_screen,
            .reverse_screen = true,
            .palette = palette,
            .foreground = .{ .r = 0xee, .g = 0xee, .b = 0xee, .a = 0xff },
            .background = .{ .r = 1, .g = 2, .b = 3, .a = 0xff },
            .cursor = .{ .r = 4, .g = 5, .b = 6, .a = 0xff },
            .cursor_text = null,
            .selection_background = null,
            .selection_foreground = null,
        },
        .rows = rows_source[0..],
        .hyperlinks = links_source[0..],
    };

    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    const snapshot = try project(allocator.allocator(), &source);
    try std.testing.expectEqual(@as(usize, 1), allocator.allocations);

    // Projection owns an immutable copy. Later source mutation cannot change the
    // view that a slow painter or observer still owns.
    first_scalars[0] = 'x';
    uri[0] = 'B';
    cells_source[0].foreground = .{ .kind = .rgb, .value = 0xaabbcc };
    rows_source[0].wrapped = false;

    try std.testing.expectEqual(@as(u64, 11), begin(snapshot).revision);
    try std.testing.expect(presentation(snapshot).reverse_screen);
    try std.testing.expectEqual(@as(usize, 1), rows(snapshot).len);
    try std.testing.expectEqual(@as(u32, 0), rows(snapshot)[0].cell_offset);
    try std.testing.expectEqual(@as(u32, 2), rows(snapshot)[0].cell_count);
    try std.testing.expect(rows(snapshot)[0].wrapped);
    try std.testing.expectEqual(@as(u8, 2), rows(snapshot)[0].line_geometry);
    try std.testing.expectEqual(@as(usize, 2), cells(snapshot).len);
    try std.testing.expectEqual(@as(u32, 0), cells(snapshot)[0].scalar_offset);
    try std.testing.expectEqual(@as(u8, 2), cells(snapshot)[0].scalar_count);
    try std.testing.expectEqual(protocol.TextColorKind.rgb, cells(snapshot)[0].foreground.kind);
    try std.testing.expectEqual(@as(u32, 0x112233), cells(snapshot)[0].foreground.value);
    try std.testing.expectEqualSlices(u32, &.{ 'e', 0x0301 }, scalars(snapshot));
    try std.testing.expectEqual(@as(usize, 1), hyperlinks(snapshot).len);
    try std.testing.expectEqual(@as(u32, 7), hyperlinks(snapshot)[0].link_id);
    try std.testing.expectEqualSlices(u8, &.{ 'A', 0, 0xff, 'Z' }, uris(snapshot));

    deinit(snapshot);
    try std.testing.expectEqual(@as(usize, 1), allocator.deallocations);
    try std.testing.expectEqual(allocator.allocated_bytes, allocator.freed_bytes);
}

test "coarse view rejects unresolved hyperlink before allocation" {
    var cell_source = [_]rich.Cell{.{
        .scalars = &.{},
        .width = 1,
        .height = 1,
        .x = 0,
        .y = 0,
        .subscale_n = 1,
        .subscale_d = 1,
        .vertical_align = 0,
        .horizontal_align = 0,
        .semantic_width = false,
        .font = 0,
        .baseline = 0,
        .underline_style = 0,
        .protection = 0,
        .style_bits = 0,
        .foreground = .{ .kind = .default, .value = 0 },
        .background = .{ .kind = .default, .value = 0 },
        .underline_color = .{ .kind = .default, .value = 0 },
        .link_id = 3,
    }};
    var row_source = [_]rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = cell_source[0..] }};
    var links_source = [_]rich.Hyperlink{};
    const palette: [256]rich.Rgba = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff });
    const source = rich.Snapshot{
        .allocator = std.testing.allocator,
        .begin = testBegin(1, 1),
        .presentation = testPresentation(palette),
        .rows = row_source[0..],
        .hyperlinks = links_source[0..],
    };

    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try std.testing.expectError(error.InvalidRichSnapshot, project(allocator.allocator(), &source));
    try std.testing.expectEqual(@as(usize, 0), allocator.allocations);
}

test "coarse view rejects malformed rich geometry before allocation" {
    var cells_source = [_]rich.Cell{};
    var rows_source = [_]rich.Row{.{
        .wrapped = false,
        .line_geometry = 0,
        .cells = cells_source[0..],
    }};
    const palette: [256]rich.Rgba = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff });
    const source = rich.Snapshot{
        .allocator = std.testing.allocator,
        .begin = testBegin(1, 1),
        .presentation = testPresentation(palette),
        .rows = rows_source[0..],
        .hyperlinks = &.{},
    };

    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try std.testing.expectError(error.InvalidRichSnapshot, project(allocator.allocator(), &source));
    try std.testing.expectEqual(@as(usize, 0), allocator.allocations);
    try std.testing.expectEqual(@as(usize, 0), allocator.allocated_bytes);
}
