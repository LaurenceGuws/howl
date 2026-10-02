//! Adapts howl-client semantic views to the terminal renderer source contract.
//!
//! This file owns storage/lifetime adaptation only. It does not render, shape,
//! rasterize, retain backend resources, or interpret terminal protocol bytes.

const std = @import("std");
const client = @import("howl_client");
const semantic = @import("source");
const View = client.view;
const Rich = client.rich;

fn style(cell: anytype) semantic.CellStyle {
    const value = View.cellStyleFromBits(cell.style_bits);
    return .{
        .bold = value.bold,
        .dim = value.dim,
        .italic = value.italic,
        .blink = value.blink,
        .blink_fast = value.blink_fast,
        .reverse = value.reverse,
        .invisible = value.invisible,
        .underline = value.underline,
        .strikethrough = value.strikethrough,
    };
}

fn color(cell: anytype, role: semantic.ColorRole) semantic.TextColor {
    const value = switch (role) {
        .foreground => cell.foreground,
        .background => cell.background,
        .underline_color => cell.underline_color,
    };
    return .{
        .kind = switch (value.kind) {
            .default => .default,
            .indexed => .indexed,
            .rgb => .rgb,
        },
        .value = value.value,
    };
}

fn sameRendition(left: anytype, right: @TypeOf(left)) bool {
    return left.style_bits == right.style_bits and left.font == right.font and
        left.baseline == right.baseline and left.underline_style == right.underline_style and
        left.protection == right.protection and left.link_id == right.link_id and
        std.meta.eql(left.foreground, right.foreground) and
        std.meta.eql(left.background, right.background) and
        std.meta.eql(left.underline_color, right.underline_color);
}

fn image(value: View.Image) semantic.Image {
    return .{
        .image_id = value.image_id,
        .generation = value.generation,
        .width = value.width,
        .height = value.height,
    };
}

fn placement(value: View.ImagePlacement) semantic.ImagePlacement {
    return .{
        .image_id = value.image_id,
        .generation = value.generation,
        .row = value.row,
        .column = value.column,
        .source_x = value.source_x,
        .source_y = value.source_y,
        .source_width = value.source_width,
        .source_height = value.source_height,
        .cell_x = value.cell_x,
        .cell_y = value.cell_y,
        .pixel_width = value.pixel_width,
        .pixel_height = value.pixel_height,
        .z = value.z,
    };
}

fn normalizeLineGeometry(value: View.LineGeometry) semantic.LineGeometry {
    return switch (value) {
        .single_width => .single_width,
        .double_width => .double_width,
        .double_height_top => .double_height_top,
        .double_height_bottom => .double_height_bottom,
    };
}

fn cursorShapeValue(value: View.CursorShape) semantic.CursorShape {
    return switch (value) {
        .block => .block,
        .underline => .underline,
        .bar => .bar,
        .none => .none,
    };
}

fn SourceMixin(comptime SnapshotType: type, comptime RowType: type, comptime CellType: type) type {
    return struct {
        pub const Snapshot = SnapshotType;
        pub const Row = RowType;
        pub const Cell = CellType;
        pub const supports_incremental = true;

        pub fn cellStyle(cell: Cell) semantic.CellStyle {
            return style(cell);
        }

        pub fn cellFont(cell: Cell) u8 {
            return cell.font;
        }

        pub fn cellBaseline(cell: Cell) u8 {
            return cell.baseline;
        }

        pub fn cellUnderlineStyle(cell: Cell) u8 {
            return cell.underline_style;
        }

        pub fn cellColor(cell: Cell, role: semantic.ColorRole) semantic.TextColor {
            return color(cell, role);
        }

        pub fn sameCellRendition(left: Cell, right: Cell) bool {
            return sameRendition(left, right);
        }

        pub fn isImagePlaceholder(_: *const Snapshot, _: usize, _: usize, sequence: []const u32) bool {
            return View.isImagePlaceholder(sequence);
        }

        pub fn graphicsImageCount(graphics: View.Graphics) usize {
            return graphics.images.len;
        }

        pub fn graphicsImage(graphics: View.Graphics, index: usize) semantic.Image {
            return image(graphics.images[index]);
        }

        pub fn graphicsPlacementCount(graphics: View.Graphics) usize {
            return graphics.placements.len;
        }

        pub fn graphicsPlacement(graphics: View.Graphics, index: usize) ?semantic.ImagePlacement {
            return placement(graphics.placements[index]);
        }

        pub fn graphicsImageVisible(_: View.Graphics, _: u32) bool {
            // Transported manifests retain only images referenced by this view.
            return true;
        }
    };
}

/// Adapts one owned immutable howl-client view.
pub const Owned = struct {
    const Mixin = SourceMixin(View.Snapshot, View.Row, View.Cell);
    pub const Snapshot = Mixin.Snapshot;
    pub const Row = Mixin.Row;
    pub const Cell = Mixin.Cell;
    pub const supports_incremental = Mixin.supports_incremental;

    pub const cellStyle = Mixin.cellStyle;
    pub const cellFont = Mixin.cellFont;
    pub const cellBaseline = Mixin.cellBaseline;
    pub const cellUnderlineStyle = Mixin.cellUnderlineStyle;
    pub const cellColor = Mixin.cellColor;
    pub const sameCellRendition = Mixin.sameCellRendition;
    pub const isImagePlaceholder = Mixin.isImagePlaceholder;
    pub const graphicsImageCount = Mixin.graphicsImageCount;
    pub const graphicsImage = Mixin.graphicsImage;
    pub const graphicsPlacementCount = Mixin.graphicsPlacementCount;
    pub const graphicsPlacement = Mixin.graphicsPlacement;
    pub const graphicsImageVisible = Mixin.graphicsImageVisible;

    pub fn rows(snapshot: *const Snapshot) u16 {
        return View.begin(snapshot).rows;
    }

    pub fn columns(snapshot: *const Snapshot) u16 {
        return View.begin(snapshot).columns;
    }

    pub fn cursorRow(snapshot: *const Snapshot) u16 {
        return View.begin(snapshot).cursor_row;
    }

    pub fn cursorColumn(snapshot: *const Snapshot) u16 {
        return View.begin(snapshot).cursor_column;
    }

    pub fn cursorVisible(snapshot: *const Snapshot) bool {
        return View.begin(snapshot).cursor_visible;
    }

    pub fn historyOffset(snapshot: *const Snapshot) u32 {
        return View.begin(snapshot).history_offset;
    }

    pub fn alternateScreen(snapshot: *const Snapshot) bool {
        return View.begin(snapshot).alternate_screen;
    }

    pub fn presentation(snapshot: *const Snapshot) *const View.Presentation {
        return View.presentation(snapshot);
    }

    pub fn rowCount(snapshot: *const Snapshot) usize {
        return View.rows(snapshot).len;
    }

    pub fn rowAt(snapshot: *const Snapshot, index: usize) Row {
        return View.rows(snapshot)[index];
    }

    pub fn rowCellCount(_: *const Snapshot, row: Row) usize {
        return row.cell_count;
    }

    pub fn cellAt(snapshot: *const Snapshot, row: Row, column: usize) Cell {
        const all = View.cells(snapshot);
        const first: usize = row.cell_offset;
        const count: usize = row.cell_count;
        std.debug.assert(first <= all.len and count <= all.len - first);
        std.debug.assert(column < count);
        return all[first + column];
    }

    pub fn cellScalars(snapshot: *const Snapshot, _: usize, _: usize, cell: Cell, _: *[24]u32) []const u32 {
        return View.cellScalars(snapshot, cell);
    }

    pub fn graphics(snapshot: *const Snapshot) View.Graphics {
        return View.graphics(snapshot);
    }

    pub fn observationRevision(snapshot: *const Snapshot) u64 {
        return View.begin(snapshot).revision;
    }

    pub fn changedRowsBaseRevision(snapshot: *const Snapshot) ?u64 {
        return View.changedRowsBaseRevision(snapshot);
    }

    pub fn changedRows(snapshot: *const Snapshot) ?[]const bool {
        return View.changedRows(snapshot);
    }

    pub fn rowShift(snapshot: *const Snapshot) ?u16 {
        return View.rowShift(snapshot);
    }

    pub fn lineGeometry(_: *const Snapshot, row: Row) semantic.LineGeometry {
        return normalizeLineGeometry(View.lineGeometry(row));
    }

    pub fn cursorShape(snapshot: *const Snapshot) semantic.CursorShape {
        return cursorShapeValue(View.cursorShape(snapshot));
    }
};

/// Adapts one already-validated borrowed howl-client rich view.
pub const RichView = struct {
    const Mixin = SourceMixin(Rich.View, Rich.Row, Rich.Cell);
    pub const Snapshot = Mixin.Snapshot;
    pub const Row = Mixin.Row;
    pub const Cell = Mixin.Cell;
    pub const supports_incremental = Mixin.supports_incremental;

    pub const cellStyle = Mixin.cellStyle;
    pub const cellFont = Mixin.cellFont;
    pub const cellBaseline = Mixin.cellBaseline;
    pub const cellUnderlineStyle = Mixin.cellUnderlineStyle;
    pub const cellColor = Mixin.cellColor;
    pub const sameCellRendition = Mixin.sameCellRendition;
    pub const isImagePlaceholder = Mixin.isImagePlaceholder;
    pub const graphicsImageCount = Mixin.graphicsImageCount;
    pub const graphicsImage = Mixin.graphicsImage;
    pub const graphicsPlacementCount = Mixin.graphicsPlacementCount;
    pub const graphicsPlacement = Mixin.graphicsPlacement;
    pub const graphicsImageVisible = Mixin.graphicsImageVisible;

    pub fn rows(snapshot: *const Snapshot) u16 {
        return snapshot.begin.rows;
    }

    pub fn columns(snapshot: *const Snapshot) u16 {
        return snapshot.begin.columns;
    }

    pub fn cursorRow(snapshot: *const Snapshot) u16 {
        return snapshot.begin.cursor_row;
    }

    pub fn cursorColumn(snapshot: *const Snapshot) u16 {
        return snapshot.begin.cursor_column;
    }

    pub fn cursorVisible(snapshot: *const Snapshot) bool {
        return snapshot.begin.cursor_visible;
    }

    pub fn historyOffset(snapshot: *const Snapshot) u32 {
        return snapshot.begin.history_offset;
    }

    pub fn alternateScreen(snapshot: *const Snapshot) bool {
        return snapshot.begin.alternate_screen;
    }

    pub fn presentation(snapshot: *const Snapshot) *const View.Presentation {
        return &snapshot.presentation;
    }

    pub fn rowCount(snapshot: *const Snapshot) usize {
        return snapshot.rows.len;
    }

    pub fn rowAt(snapshot: *const Snapshot, index: usize) Row {
        return snapshot.rows[index];
    }

    pub fn rowCellCount(_: *const Snapshot, row: Row) usize {
        return row.cells.len;
    }

    pub fn cellAt(_: *const Snapshot, row: Row, column: usize) Cell {
        std.debug.assert(column < row.cells.len);
        return row.cells[column];
    }

    pub fn cellScalars(_: *const Snapshot, _: usize, _: usize, cell: Cell, _: *[24]u32) []const u32 {
        return cell.scalars;
    }

    pub fn graphics(snapshot: *const Snapshot) View.Graphics {
        return .{
            .generation = snapshot.graphics.generation,
            .content_generation = snapshot.graphics.content_generation,
            .cell_pixel_width = snapshot.graphics.cell_pixel_width,
            .cell_pixel_height = snapshot.graphics.cell_pixel_height,
            .images = snapshot.graphics.images,
            .placements = snapshot.graphics.placements,
        };
    }

    pub fn observationRevision(snapshot: *const Snapshot) u64 {
        return snapshot.begin.revision;
    }

    pub fn changedRowsBaseRevision(snapshot: *const Snapshot) ?u64 {
        return snapshot.changed_rows_base_revision;
    }

    pub fn changedRows(snapshot: *const Snapshot) ?[]const bool {
        return snapshot.changed_rows;
    }

    pub fn rowShift(snapshot: *const Snapshot) ?u16 {
        return snapshot.row_shift;
    }

    pub fn lineGeometry(_: *const Snapshot, row: Row) semantic.LineGeometry {
        return normalizeLineGeometry(View.lineGeometryFromValue(row.line_geometry));
    }

    pub fn cursorShape(snapshot: *const Snapshot) semantic.CursorShape {
        return cursorShapeValue(View.cursorShapeFromValue(snapshot.begin.cursor_shape));
    }
};
