//! Coarse immutable native snapshot view for UI and other presentation clients.
//!
//! This module never parses `text_v1`. It projects the one accepted rich model
//! into one explicitly owned allocation and exposes only batched semantic slices.
//! The backing layout is private and is not a C/FFI ABI.

const std = @import("std");
const protocol = @import("howl_instance_protocol");
const rich = @import("rich.zig");

pub const Error = std.mem.Allocator.Error || error{
    InvalidRichSnapshot,
    ViewTooLarge,
};

pub const Begin = protocol.SnapshotBegin;
pub const Presentation = rich.Presentation;
pub const TextColor = protocol.TextColor;
pub const Image = protocol.SnapshotImage;
pub const ImagePlacement = protocol.SnapshotImagePlacement;
pub const maximum_images = protocol.graphics_v2.maximum_images;
pub const maximum_image_placements = protocol.graphics_v2.maximum_placements;

/// Semantic cell rendition exported by the projected client view.
/// Wire bit positions remain private to this module.
pub const CellStyle = struct {
    bold: bool,
    dim: bool,
    italic: bool,
    blink: bool,
    blink_fast: bool,
    reverse: bool,
    invisible: bool,
    underline: bool,
    strikethrough: bool,
};

/// Semantic cursor shape exported independently of the snapshot wire encoding.
pub const CursorShape = enum {
    block,
    underline,
    bar,
    none,
};

/// Semantic DEC row geometry exported independently of text_v1 row bytes.
pub const LineGeometry = enum {
    single_width,
    double_width,
    double_height_top,
    double_height_bottom,
};

const kitty_image_placeholder: u32 = 0x10eeee;

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

pub const Graphics = struct {
    generation: u64,
    content_generation: u64,
    cell_pixel_width: u32,
    cell_pixel_height: u32,
    images: []const Image,
    placements: []const ImagePlacement,
};

const maximum_view_bytes = protocol.maximum_text_snapshot_bytes * 2 +
    protocol.graphics_v2.maximum_manifest_bytes * 2 + std.math.maxInt(u16) + protocol.properties.maximum_bytes;

const Impl = struct {
    allocator: std.mem.Allocator,
    word_count: usize,
    total_bytes: usize,
    rows_offset: usize,
    cells_offset: usize,
    scalars_offset: usize,
    hyperlinks_offset: usize,
    uris_offset: usize,
    images_offset: usize,
    placements_offset: usize,
    changed_rows_offset: usize,
    properties_offset: usize,
    properties_bytes: usize,
    row_count: usize,
    cell_count: usize,
    scalar_count: usize,
    hyperlink_count: usize,
    uri_bytes: usize,
    image_count: usize,
    placement_count: usize,
    changed_rows_present: bool,
    row_shift: ?u16,
    graphics_generation: u64,
    graphics_content_generation: u64,
    graphics_cell_pixel_width: u32,
    graphics_cell_pixel_height: u32,
    begin: Begin,
    presentation: Presentation,
};

comptime {
    if (@alignOf(Impl) > @alignOf(u128)) @compileError("view owner alignment exceeds backing allocation");

    // `rich.receive` caps `text_v1` at 4 MiB and graphics metadata separately.
    // Prove that every coarse fixed record costs at most twice its corresponding
    // frozen wire record. Scalar and URI payload bytes retain their native byte
    // width. The fixed owner plus worst section-alignment padding must likewise
    // fit inside twice the snapshot begin/presentation/graphics/end overhead.
    const row_wire_fixed = protocol.header_bytes +
        protocol.text_v1.record_header_bytes + protocol.text_v1.row_header_bytes;
    const hyperlink_wire_fixed = protocol.header_bytes +
        protocol.text_v1.record_header_bytes + protocol.text_v1.hyperlink_header_bytes;
    const fixed_wire = protocol.header_bytes + protocol.payload_bytes.snapshot_begin +
        protocol.header_bytes + protocol.text_v1.record_header_bytes + protocol.text_v1.presentation_bytes +
        protocol.header_bytes + protocol.graphics_v2.manifest_header_bytes +
        protocol.header_bytes + protocol.properties.header_bytes +
        protocol.header_bytes + protocol.payload_bytes.snapshot_end;
    const fixed_view = @sizeOf(Impl) +
        (@alignOf(Row) - 1) + (@alignOf(Cell) - 1) +
        (@alignOf(u32) - 1) + (@alignOf(Hyperlink) - 1) +
        (@alignOf(Image) - 1) + (@alignOf(ImagePlacement) - 1);

    if (@sizeOf(Row) > row_wire_fixed * 2) @compileError("coarse row exceeds 2x wire bound");
    if (@sizeOf(Cell) > protocol.text_v1.cell_header_bytes * 2) @compileError("coarse cell exceeds 2x wire bound");
    if (@sizeOf(u32) != 4) @compileError("coarse scalar no longer matches text_v1 scalar width");
    if (@sizeOf(Hyperlink) > hyperlink_wire_fixed * 2) @compileError("coarse hyperlink exceeds 2x wire bound");
    if (@sizeOf(Image) > protocol.graphics_v2.image_bytes * 2)
        @compileError("coarse image descriptor exceeds 2x wire bound");
    if (@sizeOf(ImagePlacement) > protocol.graphics_v2.placement_bytes * 2)
        @compileError("coarse image placement exceeds 2x wire bound");
    if (fixed_view > fixed_wire * 2) @compileError("coarse fixed owner exceeds 2x wire bound");
}

/// Projects one already-decoded rich snapshot into one immutable allocation.
///
/// The caller owns the returned view and must call `deinit`. The source may be
/// released immediately after this returns.
pub fn project(allocator: std.mem.Allocator, source: *const rich.Snapshot) Error!*Snapshot {
    const borrowed = source.view();
    return projectView(allocator, &borrowed);
}

/// Projects one borrowed rich view into one immutable owned coarse snapshot.
pub fn projectView(allocator: std.mem.Allocator, source: *const rich.View) Error!*Snapshot {
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
    const uris_end = std.math.add(usize, uris_offset, counts.uri_bytes) catch
        return error.ViewTooLarge;
    const images_offset = alignAfter(Image, uris_end);
    const images_end = try sectionEnd(Image, images_offset, source.graphics.images.len);
    const placements_offset = alignAfter(ImagePlacement, images_end);
    const placements_end = try sectionEnd(
        ImagePlacement,
        placements_offset,
        source.graphics.placements.len,
    );
    const changed_rows_offset = placements_end;
    // The coarse presentation layer only retains a repair mask when v7 also
    // supplied an explicit row rotation. RawCache may expose same-index change
    // facts on ordinary frames, but those remain an internal decode detail.
    const changed_rows_count = if (source.row_shift != null) source.rows.len else 0;
    const properties_offset = try sectionEnd(bool, changed_rows_offset, changed_rows_count);
    const properties_bytes = protocol.properties.encodedSize(source.properties) catch return error.InvalidRichSnapshot;
    const total_bytes = std.math.add(usize, properties_offset, properties_bytes) catch return error.ViewTooLarge;
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
        .images_offset = images_offset,
        .placements_offset = placements_offset,
        .changed_rows_offset = changed_rows_offset,
        .properties_offset = properties_offset,
        .properties_bytes = properties_bytes,
        .row_count = source.rows.len,
        .cell_count = counts.cells,
        .scalar_count = counts.scalars,
        .hyperlink_count = source.hyperlinks.len,
        .uri_bytes = counts.uri_bytes,
        .image_count = source.graphics.images.len,
        .placement_count = source.graphics.placements.len,
        .changed_rows_present = source.row_shift != null,
        .row_shift = source.row_shift,
        .graphics_generation = source.graphics.generation,
        .graphics_content_generation = source.graphics.content_generation,
        .graphics_cell_pixel_width = source.graphics.cell_pixel_width,
        .graphics_cell_pixel_height = source.graphics.cell_pixel_height,
        .begin = source.begin,
        .presentation = source.presentation,
    };

    const output_rows = mutableSliceAt(Row, bytes, rows_offset, source.rows.len);
    const output_cells = mutableSliceAt(Cell, bytes, cells_offset, counts.cells);
    const output_scalars = mutableSliceAt(u32, bytes, scalars_offset, counts.scalars);
    const output_links = mutableSliceAt(Hyperlink, bytes, hyperlinks_offset, source.hyperlinks.len);
    const output_uris = bytes[uris_offset .. uris_offset + counts.uri_bytes];
    const output_images = mutableSliceAt(Image, bytes, images_offset, source.graphics.images.len);
    const output_placements = mutableSliceAt(
        ImagePlacement,
        bytes,
        placements_offset,
        source.graphics.placements.len,
    );
    const output_changed_rows = mutableSliceAt(
        bool,
        bytes,
        changed_rows_offset,
        changed_rows_count,
    );

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
    @memcpy(output_images, source.graphics.images);
    @memcpy(output_placements, source.graphics.placements);
    if (source.row_shift != null) @memcpy(output_changed_rows, source.changed_rows.?);
    const written_properties = protocol.properties.encode(bytes[properties_offset..][0..properties_bytes], source.properties) catch
        return error.InvalidRichSnapshot;
    std.debug.assert(written_properties == properties_bytes);

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

/// Borrows coherent terminal properties from the accepted immutable snapshot.
pub fn properties(snapshot: *const Snapshot) protocol.properties.View {
    const impl = constImpl(snapshot);
    return protocol.properties.decode(ownerBytes(impl)[impl.properties_offset..][0..impl.properties_bytes]) catch unreachable;
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

/// Resolves one already-validated rich/view style bitfield into semantic rendition.
pub fn cellStyleFromBits(style_bits: u16) CellStyle {
    return .{
        .bold = style_bits & protocol.text_v1.style.bold != 0,
        .dim = style_bits & protocol.text_v1.style.dim != 0,
        .italic = style_bits & protocol.text_v1.style.italic != 0,
        .blink = style_bits & protocol.text_v1.style.blink != 0,
        .blink_fast = style_bits & protocol.text_v1.style.blink_fast != 0,
        .reverse = style_bits & protocol.text_v1.style.reverse != 0,
        .invisible = style_bits & protocol.text_v1.style.invisible != 0,
        .underline = style_bits & protocol.text_v1.style.underline != 0,
        .strikethrough = style_bits & protocol.text_v1.style.strikethrough != 0,
    };
}

/// Resolves validated cell rendition without exposing text_v1 style bits.
pub fn cellStyle(cell: Cell) CellStyle {
    return cellStyleFromBits(cell.style_bits);
}

/// Resolves one already-validated rich/view cursor-shape value.
pub fn cursorShapeFromValue(value: u8) CursorShape {
    return switch (value) {
        0 => .block,
        1 => .underline,
        2 => .bar,
        3 => .none,
        else => unreachable,
    };
}

/// Resolves the validated snapshot cursor shape without exposing wire values.
pub fn cursorShape(snapshot: *const Snapshot) CursorShape {
    return cursorShapeFromValue(begin(snapshot).cursor_shape);
}

/// Resolves one already-validated rich/view DEC row-geometry value.
pub fn lineGeometryFromValue(value: u8) LineGeometry {
    return switch (value) {
        0 => .single_width,
        1 => .double_width,
        2 => .double_height_top,
        3 => .double_height_bottom,
        else => unreachable,
    };
}

/// Resolves validated DEC row geometry without exposing text_v1 numeric values.
pub fn lineGeometry(row: Row) LineGeometry {
    return lineGeometryFromValue(row.line_geometry);
}

/// Borrows exactly one projected cell's scalar sequence.
pub fn cellScalars(snapshot: *const Snapshot, cell: Cell) []const u32 {
    const values = scalars(snapshot);
    const first: usize = cell.scalar_offset;
    const count: usize = cell.scalar_count;
    std.debug.assert(first <= values.len and count <= values.len - first);
    return values[first .. first + count];
}

/// Reports the Kitty Unicode-placement placeholder semantic without leaking its
/// private scalar identity to presentation consumers.
pub fn isImagePlaceholder(sequence: []const u32) bool {
    return sequence.len != 0 and sequence[0] == kitty_image_placeholder;
}

pub fn hyperlinks(snapshot: *const Snapshot) []const Hyperlink {
    const impl = constImpl(snapshot);
    return constSliceAt(Hyperlink, ownerBytes(impl), impl.hyperlinks_offset, impl.hyperlink_count);
}

pub fn uris(snapshot: *const Snapshot) []const u8 {
    const impl = constImpl(snapshot);
    return ownerBytes(impl)[impl.uris_offset .. impl.uris_offset + impl.uri_bytes];
}

pub fn graphics(snapshot: *const Snapshot) Graphics {
    const impl = constImpl(snapshot);
    const bytes = ownerBytes(impl);
    return .{
        .generation = impl.graphics_generation,
        .content_generation = impl.graphics_content_generation,
        .cell_pixel_width = impl.graphics_cell_pixel_width,
        .cell_pixel_height = impl.graphics_cell_pixel_height,
        .images = constSliceAt(Image, bytes, impl.images_offset, impl.image_count),
        .placements = constSliceAt(
            ImagePlacement,
            bytes,
            impl.placements_offset,
            impl.placement_count,
        ),
    };
}

/// Exact row-repair mask retained from one reusable rich observation. `null`
/// means the source did not provide incremental row facts.
pub fn changedRows(snapshot: *const Snapshot) ?[]const bool {
    const impl = constImpl(snapshot);
    if (!impl.changed_rows_present) return null;
    return constSliceAt(bool, ownerBytes(impl), impl.changed_rows_offset, impl.row_count);
}

/// Explicit upward baseline rotation applied before `changedRows` repairs.
pub fn rowShift(snapshot: *const Snapshot) ?u16 {
    return constImpl(snapshot).row_shift;
}

pub const TextProjection = struct {
    bytes_written: usize,
    truncated: bool,
    /// Unicode scalar count, not UTF-8 bytes or terminal columns.
    character_count: usize = 0,
    /// Live cursor's scalar offset when requested and represented in the buffer.
    caret_offset: ?usize = null,
};

const OwnedTextSource = struct {
    const SnapshotType = Snapshot;
    const RowType = Row;
    const CellType = Cell;

    fn beginFacts(snapshot: *const Snapshot) *const Begin {
        return begin(snapshot);
    }

    fn snapshotRows(snapshot: *const Snapshot) []const Row {
        return rows(snapshot);
    }

    fn rowCells(snapshot: *const Snapshot, row: Row) []const Cell {
        const values = cells(snapshot);
        return values[row.cell_offset .. row.cell_offset + row.cell_count];
    }

    fn cellScalarsFor(snapshot: *const Snapshot, cell: Cell) []const u32 {
        return cellScalars(snapshot, cell);
    }

    fn cellVisible(cell: Cell) bool {
        return !cellStyle(cell).invisible;
    }
};

const RichTextSource = struct {
    const SnapshotType = rich.View;
    const RowType = rich.Row;
    const CellType = rich.Cell;

    fn beginFacts(snapshot: *const rich.View) *const Begin {
        return &snapshot.begin;
    }

    fn snapshotRows(snapshot: *const rich.View) []const rich.Row {
        return snapshot.rows;
    }

    fn rowCells(_: *const rich.View, row: rich.Row) []const rich.Cell {
        return row.cells;
    }

    fn cellScalarsFor(_: *const rich.View, cell: rich.Cell) []const u32 {
        return cell.scalars;
    }

    fn cellVisible(cell: rich.Cell) bool {
        return !cellStyleFromBits(cell.style_bits).invisible;
    }
};

/// Writes one bounded UTF-8 projection of the currently projected viewport.
///
/// Visual row boundaries and interior blank cells are retained, while trailing
/// blank cells/rows are trimmed. Multicell continuation fragments do not repeat
/// text and concealed cells project as blanks. The caller owns the output
/// buffer; exhaustion truncates rather than allocating or failing the snapshot.
pub fn writeVisibleText(snapshot: *const Snapshot, output: []u8) TextProjection {
    return writeText(OwnedTextSource, snapshot, output, false);
}

/// Borrowed-rich equivalent of writeVisibleText. The caller retains every
/// rich slice for this synchronous call; no presentation ownership is created.
pub fn writeVisibleRichText(snapshot: *const rich.View, output: []u8) TextProjection {
    return writeText(RichTextSource, snapshot, output, false);
}

/// Projects the same canonical visible text for accessibility, retaining blanks
/// through the live cursor so its scalar offset is exact. History has no live
/// caret. Concealed cells remain blanks and multicell fragments never repeat.
/// No host, accessibility protocol, or renderer state is retained here.
pub fn writeAccessibleText(snapshot: *const Snapshot, output: []u8) TextProjection {
    return writeText(OwnedTextSource, snapshot, output, true);
}

fn writeText(
    comptime Source: type,
    snapshot: *const Source.SnapshotType,
    output: []u8,
    include_cursor: bool,
) TextProjection {
    var writer = TextWriter{ .bytes = output };
    const snapshot_rows = Source.snapshotRows(snapshot);
    const facts = Source.beginFacts(snapshot);
    var cursor_row: usize = facts.cursor_row;
    var cursor_column: usize = facts.cursor_column;
    var has_cursor = include_cursor and facts.history_offset == 0 and
        facts.cursor_visible and cursor_row < snapshot_rows.len and
        cursor_column < Source.rowCells(snapshot, snapshot_rows[cursor_row]).len;
    if (has_cursor) {
        const cell = Source.rowCells(snapshot, snapshot_rows[cursor_row])[cursor_column];
        has_cursor = cell.y <= cursor_row and cell.x <= cursor_column;
        if (has_cursor) {
            cursor_row -= cell.y;
            cursor_column -= cell.x;
        }
    }
    var last_row = lastTextRow(Source, snapshot, snapshot_rows);
    if (has_cursor) last_row = @max(last_row orelse 0, cursor_row);
    const end_row = last_row orelse return .{ .bytes_written = 0, .truncated = false };
    var caret_offset: ?usize = null;
    for (snapshot_rows[0 .. end_row + 1], 0..) |row, row_index| {
        if (row_index != 0 and !writer.writeByte('\n')) break;
        const row_cells = Source.rowCells(snapshot, row);
        var last_cell = lastTextCell(Source, snapshot, row_cells);
        if (has_cursor and row_index == cursor_row)
            last_cell = @max(last_cell orelse 0, cursor_column);
        const end_cell = last_cell orelse continue;
        for (row_cells[0 .. end_cell + 1], 0..) |cell, column| {
            if (has_cursor and row_index == cursor_row and column == cursor_column)
                caret_offset = writer.character_count;
            if (cell.x != 0 or cell.y != 0) continue;
            const cell_scalars = Source.cellScalarsFor(snapshot, cell);
            if (!Source.cellVisible(cell) or cell_scalars.len == 0) {
                if (!writer.writeByte(' ')) break;
                continue;
            }
            for (cell_scalars) |scalar| {
                if (!writer.writeScalar(scalar)) break;
            }
            if (writer.truncated) break;
        }
        if (writer.truncated) break;
    }
    return .{
        .bytes_written = writer.offset,
        .truncated = writer.truncated,
        .character_count = writer.character_count,
        .caret_offset = caret_offset,
    };
}

const TextWriter = struct {
    bytes: []u8,
    offset: usize = 0,
    character_count: usize = 0,
    truncated: bool = false,

    fn writeByte(self: *TextWriter, value: u8) bool {
        if (self.offset == self.bytes.len) {
            self.truncated = true;
            return false;
        }
        self.bytes[self.offset] = value;
        self.offset += 1;
        self.character_count += 1;
        return true;
    }

    fn writeScalar(self: *TextWriter, scalar: u32) bool {
        var encoded: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(@intCast(scalar), &encoded) catch unreachable;
        if (len > self.bytes.len - self.offset) {
            self.truncated = true;
            return false;
        }
        @memcpy(self.bytes[self.offset .. self.offset + len], encoded[0..len]);
        self.offset += len;
        self.character_count += 1;
        return true;
    }
};

fn lastTextRow(
    comptime Source: type,
    snapshot: *const Source.SnapshotType,
    snapshot_rows: []const Source.RowType,
) ?usize {
    var index = snapshot_rows.len;
    while (index > 0) {
        index -= 1;
        if (lastTextCell(Source, snapshot, Source.rowCells(snapshot, snapshot_rows[index])) != null)
            return index;
    }
    return null;
}

fn lastTextCell(
    comptime Source: type,
    snapshot: *const Source.SnapshotType,
    row_cells: []const Source.CellType,
) ?usize {
    var index = row_cells.len;
    while (index > 0) {
        index -= 1;
        const cell = row_cells[index];
        if (cell.x == 0 and cell.y == 0 and Source.cellVisible(cell) and
            Source.cellScalarsFor(snapshot, cell).len != 0)
            return index;
    }
    return null;
}

const Counts = struct {
    cells: usize,
    scalars: usize,
    uri_bytes: usize,
};

fn validateAndCount(source: *const rich.View) Error!Counts {
    if (source.rows.len != source.begin.rows or source.begin.cursor_shape > 3) {
        return error.InvalidRichSnapshot;
    }
    if (source.changed_rows) |changed| {
        if (changed.len != source.rows.len) return error.InvalidRichSnapshot;
    } else if (source.row_shift != null) {
        return error.InvalidRichSnapshot;
    }
    if (source.row_shift) |shift| {
        if (shift == 0 or shift >= source.begin.rows) return error.InvalidRichSnapshot;
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
    if (!validGraphics(source)) return error.InvalidRichSnapshot;

    if (cell_count > std.math.maxInt(u32) or
        scalar_count > std.math.maxInt(u32) or
        uri_bytes > std.math.maxInt(u32))
    {
        return error.ViewTooLarge;
    }
    return .{ .cells = cell_count, .scalars = scalar_count, .uri_bytes = uri_bytes };
}

fn validGraphics(source: *const rich.View) bool {
    if (source.graphics.images.len > protocol.graphics_v2.maximum_images or
        source.graphics.placements.len > protocol.graphics_v2.maximum_placements)
        return false;
    if ((source.graphics.images.len != 0 or source.graphics.placements.len != 0) and
        (source.graphics.cell_pixel_width == 0 or source.graphics.cell_pixel_height == 0))
        return false;
    for (source.graphics.images, 0..) |image, index| {
        if (image.image_id == 0 or image.generation == 0 or image.width == 0 or image.height == 0 or
            image.width > protocol.graphics_v2.maximum_dimension or
            image.height > protocol.graphics_v2.maximum_dimension or
            @as(u64, image.width) * @as(u64, image.height) * 4 > protocol.graphics_v2.maximum_image_bytes)
            return false;
        for (source.graphics.images[0..index]) |prior| if (prior.image_id == image.image_id)
            return false;
    }
    var referenced: [protocol.graphics_v2.maximum_images]bool = @splat(false);
    for (source.graphics.placements) |placement| {
        if (placement.image_id == 0 or placement.generation == 0 or
            placement.row >= source.begin.rows or placement.column >= source.begin.columns or
            placement.source_width == 0 or placement.source_height == 0 or
            placement.pixel_width == 0 or placement.pixel_height == 0)
            return false;
        const image_index = richImageIndex(source.graphics.images, placement.image_id) orelse return false;
        const image = source.graphics.images[image_index];
        if (placement.source_x > image.width or placement.source_y > image.height or
            placement.source_width > image.width - placement.source_x or
            placement.source_height > image.height - placement.source_y)
            return false;
        referenced[image_index] = true;
    }
    for (referenced[0..source.graphics.images.len]) |used| if (!used) return false;
    return true;
}

fn richImageIndex(images: []const protocol.SnapshotImage, image_id: u32) ?usize {
    for (images, 0..) |image, index| if (image.image_id == image_id) return index;
    return null;
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

fn testCell(scalar_values: []const u32) rich.Cell {
    return .{
        .scalars = scalar_values,
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
        .link_id = 0,
    };
}

test "visible text projection preserves blanks and suppresses concealed continuations" {
    var row_zero_cells = [_]rich.Cell{
        testCell(&.{'A'}),
        testCell(&.{}),
        testCell(&.{'X'}),
        testCell(&.{0x754c}),
        testCell(&.{}),
    };
    row_zero_cells[2].style_bits = protocol.text_v1.style.invisible;
    row_zero_cells[3].width = 2;
    row_zero_cells[4].width = 2;
    row_zero_cells[4].x = 1;
    var row_one_cells = [_]rich.Cell{ testCell(&.{'B'}), testCell(&.{}), testCell(&.{}), testCell(&.{}), testCell(&.{}) };
    var row_two_cells = [_]rich.Cell{ testCell(&.{}), testCell(&.{}), testCell(&.{}), testCell(&.{}), testCell(&.{}) };
    var rows_source = [_]rich.Row{
        .{ .wrapped = false, .line_geometry = 0, .cells = &row_zero_cells },
        .{ .wrapped = false, .line_geometry = 0, .cells = &row_one_cells },
        .{ .wrapped = false, .line_geometry = 0, .cells = &row_two_cells },
    };
    const palette: [256]rich.Rgba = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff });
    const source = rich.Snapshot{
        .allocator = std.testing.allocator,
        .begin = testBegin(3, 5),
        .presentation = testPresentation(palette),
        .rows = &rows_source,
        .hyperlinks = &.{},
    };
    const snapshot = try project(std.testing.allocator, &source);
    defer deinit(snapshot);
    var output: [64]u8 = undefined;
    const result = writeVisibleText(snapshot, &output);
    try std.testing.expect(!result.truncated);
    try std.testing.expectEqualStrings("A  界\nB", output[0..result.bytes_written]);

    const borrowed = source.view();
    var rich_output: [64]u8 = undefined;
    const rich_result = writeVisibleRichText(&borrowed, &rich_output);
    try std.testing.expectEqual(result, rich_result);
    try std.testing.expectEqualSlices(u8, output[0..result.bytes_written], rich_output[0..rich_result.bytes_written]);

    var short: [4]u8 = undefined;
    const short_result = writeVisibleText(snapshot, &short);
    try std.testing.expect(short_result.truncated);
    try std.testing.expectEqualStrings("A  ", short[0..short_result.bytes_written]);
    var rich_short: [4]u8 = undefined;
    const rich_short_result = writeVisibleRichText(&borrowed, &rich_short);
    try std.testing.expectEqual(short_result, rich_short_result);
    try std.testing.expectEqualSlices(u8, short[0..short_result.bytes_written], rich_short[0..rich_short_result.bytes_written]);
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
    var image_source = [_]protocol.SnapshotImage{.{
        .image_id = 9,
        .generation = 12,
        .width = 2,
        .height = 3,
    }};
    var placement_source = [_]protocol.SnapshotImagePlacement{.{
        .image_id = 9,
        .generation = 13,
        .row = 0,
        .column = 1,
        .source_x = 0,
        .source_y = 1,
        .source_width = 2,
        .source_height = 2,
        .cell_x = 1,
        .cell_y = 2,
        .pixel_width = 20,
        .pixel_height = 30,
        .z = -2,
    }};
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
        .properties = .{ .title = &uri, .progress = .{ .kind = .normal, .value = 61 } },
        .graphics = .{
            .generation = 14,
            .content_generation = 12,
            .cell_pixel_width = 10,
            .cell_pixel_height = 20,
            .images = &image_source,
            .placements = &placement_source,
        },
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
    image_source[0].width = 1;
    placement_source[0].z = 99;

    try std.testing.expectEqual(@as(u64, 11), begin(snapshot).revision);
    try std.testing.expect(presentation(snapshot).reverse_screen);
    try std.testing.expectEqual(@as(usize, 1), rows(snapshot).len);
    try std.testing.expectEqual(@as(u32, 0), rows(snapshot)[0].cell_offset);
    try std.testing.expectEqual(@as(u32, 2), rows(snapshot)[0].cell_count);
    try std.testing.expect(rows(snapshot)[0].wrapped);
    try std.testing.expectEqual(@as(u8, 2), rows(snapshot)[0].line_geometry);
    try std.testing.expectEqual(LineGeometry.double_height_top, lineGeometry(rows(snapshot)[0]));
    try std.testing.expectEqual(CursorShape.bar, cursorShape(snapshot));
    try std.testing.expectEqual(@as(usize, 2), cells(snapshot).len);
    try std.testing.expectEqual(@as(u32, 0), cells(snapshot)[0].scalar_offset);
    try std.testing.expectEqual(@as(u8, 2), cells(snapshot)[0].scalar_count);
    try std.testing.expectEqual(protocol.TextColorKind.rgb, cells(snapshot)[0].foreground.kind);
    try std.testing.expectEqual(@as(u32, 0x112233), cells(snapshot)[0].foreground.value);
    const style = cellStyle(cells(snapshot)[0]);
    try std.testing.expect(style.bold);
    try std.testing.expect(style.underline);
    try std.testing.expect(!style.dim and !style.reverse and !style.invisible);
    try std.testing.expectEqualSlices(u32, &.{ 'e', 0x0301 }, cellScalars(snapshot, cells(snapshot)[0]));
    try std.testing.expectEqualSlices(u32, &.{ 'e', 0x0301 }, scalars(snapshot));
    try std.testing.expectEqual(@as(usize, 1), hyperlinks(snapshot).len);
    try std.testing.expectEqual(@as(u32, 7), hyperlinks(snapshot)[0].link_id);
    try std.testing.expectEqualSlices(u8, &.{ 'A', 0, 0xff, 'Z' }, uris(snapshot));
    const property_view = properties(snapshot);
    try std.testing.expectEqualSlices(u8, &.{ 'A', 0, 0xff, 'Z' }, property_view.title.?);
    try std.testing.expectEqualDeep(protocol.properties.Progress{ .kind = .normal, .value = 61 }, property_view.progress);
    const image_view = graphics(snapshot);
    try std.testing.expectEqual(@as(u64, 14), image_view.generation);
    try std.testing.expectEqual(@as(u64, 12), image_view.content_generation);
    try std.testing.expectEqual(@as(u32, 10), image_view.cell_pixel_width);
    try std.testing.expectEqual(@as(u32, 20), image_view.cell_pixel_height);
    try std.testing.expectEqual(@as(usize, 1), image_view.images.len);
    try std.testing.expectEqual(@as(u32, 2), image_view.images[0].width);
    try std.testing.expectEqual(@as(usize, 1), image_view.placements.len);
    try std.testing.expectEqual(@as(i32, -2), image_view.placements[0].z);

    deinit(snapshot);
    try std.testing.expectEqual(@as(usize, 1), allocator.deallocations);
    try std.testing.expectEqual(allocator.allocated_bytes, allocator.freed_bytes);
}

test "coarse view owns exact incremental row hints" {
    var row_zero_cells = [_]rich.Cell{testCell(&.{'A'})};
    var row_one_cells = [_]rich.Cell{testCell(&.{'B'})};
    var rows_source = [_]rich.Row{
        .{ .wrapped = false, .line_geometry = 0, .cells = &row_zero_cells },
        .{ .wrapped = false, .line_geometry = 0, .cells = &row_one_cells },
    };
    var changed = [_]bool{ false, true };
    const palette: [256]rich.Rgba = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff });
    const source = rich.View{
        .begin = testBegin(2, 1),
        .presentation = testPresentation(palette),
        .rows = &rows_source,
        .hyperlinks = &.{},
        .graphics = .{},
        .changed_rows = &changed,
        .row_shift = 1,
    };
    const snapshot = try projectView(std.testing.allocator, &source);
    defer deinit(snapshot);

    changed = .{ true, false };
    try std.testing.expectEqual(@as(?u16, 1), rowShift(snapshot));
    try std.testing.expectEqualSlices(bool, &.{ false, true }, changedRows(snapshot).?);

    var malformed = source;
    malformed.changed_rows = changed[0..1];
    try std.testing.expectError(
        error.InvalidRichSnapshot,
        projectView(std.testing.allocator, &malformed),
    );
    malformed = source;
    malformed.changed_rows = null;
    try std.testing.expectError(
        error.InvalidRichSnapshot,
        projectView(std.testing.allocator, &malformed),
    );
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

test "coarse view rejects unknown cursor wire shape before allocation" {
    const palette: [256]rich.Rgba = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff });
    var begin_value = testBegin(0, 0);
    begin_value.cursor_shape = 4;
    const source = rich.Snapshot{
        .allocator = std.testing.allocator,
        .begin = begin_value,
        .presentation = testPresentation(palette),
        .rows = &.{},
        .hyperlinks = &.{},
    };

    var allocator = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    try std.testing.expectError(error.InvalidRichSnapshot, project(allocator.allocator(), &source));
    try std.testing.expectEqual(@as(usize, 0), allocator.allocations);
}

test "accessible text keeps canonical Unicode caret and conceals hidden text" {
    var cells_source = [_]rich.Cell{
        testCell(&.{ 'e', 0x0301 }), testCell(&.{0x754c}), testCell(&.{}),
        testCell(&.{'X'}),           testCell(&.{}),       testCell(&.{}),
    };
    cells_source[1].width = 2;
    cells_source[2].width = 2;
    cells_source[2].x = 1;
    cells_source[3].style_bits = protocol.text_v1.style.invisible;
    var rows_source = [_]rich.Row{.{ .wrapped = false, .line_geometry = 0, .cells = &cells_source }};
    const palette: [256]rich.Rgba = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff });
    var source = rich.Snapshot{
        .allocator = std.testing.allocator,
        .begin = testBegin(1, 6),
        .presentation = testPresentation(palette),
        .rows = &rows_source,
        .hyperlinks = &.{},
    };
    source.begin.cursor_visible = true;
    source.begin.cursor_column = 5;
    const snapshot = try project(std.testing.allocator, &source);
    defer deinit(snapshot);
    var output: [64]u8 = undefined;
    const result = writeAccessibleText(snapshot, &output);
    try std.testing.expectEqualStrings("é界   ", output[0..result.bytes_written]);
    try std.testing.expectEqual(@as(usize, 6), result.character_count);
    try std.testing.expectEqual(@as(?usize, 5), result.caret_offset);
    try std.testing.expect(!result.truncated);

    var small: [4]u8 = undefined;
    const short = writeAccessibleText(snapshot, &small);
    try std.testing.expectEqualStrings("é", small[0..short.bytes_written]);
    try std.testing.expect(short.truncated);
    try std.testing.expectEqual(@as(?usize, null), short.caret_offset);

    source.begin.cursor_column = 2;
    const wide = try project(std.testing.allocator, &source);
    defer deinit(wide);
    const wide_result = writeAccessibleText(wide, &output);
    try std.testing.expectEqual(@as(?usize, 2), wide_result.caret_offset);

    source.begin.history_count = 1;
    source.begin.history_offset = 1;
    const history = try project(std.testing.allocator, &source);
    defer deinit(history);
    const history_result = writeAccessibleText(history, &output);
    try std.testing.expectEqual(@as(?usize, null), history_result.caret_offset);
    try std.testing.expectEqualStrings("é界", output[0..history_result.bytes_written]);
}

test "accessible text retains empty rows through cursor without allocating" {
    var row_cells = [_]rich.Cell{ testCell(&.{}), testCell(&.{}), testCell(&.{}) };
    var rows_source = [_]rich.Row{
        .{ .wrapped = false, .line_geometry = 0, .cells = &row_cells },
        .{ .wrapped = false, .line_geometry = 0, .cells = &row_cells },
    };
    const palette: [256]rich.Rgba = @splat(.{ .r = 0, .g = 0, .b = 0, .a = 0xff });
    var source = rich.Snapshot{
        .allocator = std.testing.allocator,
        .begin = testBegin(2, 3),
        .presentation = testPresentation(palette),
        .rows = &rows_source,
        .hyperlinks = &.{},
    };
    source.begin.cursor_visible = true;
    source.begin.cursor_row = 1;
    source.begin.cursor_column = 2;
    const snapshot = try project(std.testing.allocator, &source);
    defer deinit(snapshot);
    var output: [16]u8 = undefined;
    const result = writeAccessibleText(snapshot, &output);
    try std.testing.expectEqualStrings("\n   ", output[0..result.bytes_written]);
    try std.testing.expectEqual(@as(?usize, 3), result.caret_offset);
    try std.testing.expectEqual(@as(usize, 4), result.character_count);
    const empty = writeAccessibleText(snapshot, &.{});
    try std.testing.expect(empty.truncated);
    try std.testing.expectEqual(@as(?usize, null), empty.caret_offset);
    const visible = writeVisibleText(snapshot, &output);
    try std.testing.expectEqual(@as(usize, 0), visible.bytes_written);
}
