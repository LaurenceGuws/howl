//! Adapts a borrowed howl-vt observation to the terminal renderer source contract.
//!
//! The snapshot exists only for one synchronous projection call. No VT storage
//! or observation borrow survives the update.

const std = @import("std");
const VT = @import("howl_vt").Terminal;
const semantic = @import("source");

const kitty_image_placeholder: u32 = 0x10eeee;

pub const Source = struct {
    pub const Snapshot = struct {
        view: VT.SemanticView,
        colors: VT.Presentation,
        images: VT.Images,
    };

    pub const Row = u16;
    pub const Cell = VT.Cell;
    pub const supports_incremental = false;

    pub fn rows(snapshot: *const Snapshot) u16 {
        return snapshot.view.rows;
    }

    pub fn columns(snapshot: *const Snapshot) u16 {
        return snapshot.view.cols;
    }

    pub fn cursorRow(snapshot: *const Snapshot) u16 {
        return snapshot.view.cursor_row;
    }

    pub fn cursorColumn(snapshot: *const Snapshot) u16 {
        return snapshot.view.cursor_col;
    }

    pub fn cursorVisible(snapshot: *const Snapshot) bool {
        return snapshot.view.cursor_visible;
    }

    pub fn historyOffset(snapshot: *const Snapshot) u32 {
        return snapshot.view.history_offset;
    }

    pub fn alternateScreen(snapshot: *const Snapshot) bool {
        return snapshot.view.is_alternate_screen;
    }

    pub fn presentation(snapshot: *const Snapshot) *const VT.Presentation {
        return &snapshot.colors;
    }

    pub fn rowCount(snapshot: *const Snapshot) usize {
        return snapshot.view.rows;
    }

    pub fn rowAt(_: *const Snapshot, index: usize) Row {
        return @intCast(index);
    }

    pub fn rowCellCount(snapshot: *const Snapshot, _: Row) usize {
        return snapshot.view.cols;
    }

    pub fn cellAt(snapshot: *const Snapshot, row: Row, column: usize) Cell {
        return snapshot.view.cellInfoAt(row, @intCast(column));
    }

    pub fn lineGeometry(snapshot: *const Snapshot, row: Row) semantic.LineGeometry {
        return switch (snapshot.view.lineGeometry(row)) {
            .single_width => .single_width,
            .double_width => .double_width,
            .double_height_top => .double_height_top,
            .double_height_bottom => .double_height_bottom,
        };
    }

    pub fn cellScalars(
        snapshot: *const Snapshot,
        row: usize,
        column: usize,
        cell: Cell,
        output: *[24]u32,
    ) []const u32 {
        if (cell.x != 0 or cell.y != 0 or cell.codepoint == 0) return &.{};
        if (cell.combining_len == 0) {
            output[0] = cell.codepoint;
            return output[0..1];
        }
        var scalars: [24]u21 = undefined;
        const sequence = snapshot.view.cellScalarsAt(@intCast(row), @intCast(column), &scalars);
        for (sequence, 0..) |scalar, index| output[index] = scalar;
        return output[0..sequence.len];
    }

    pub fn cellStyle(cell: Cell) semantic.CellStyle {
        return .{
            .bold = cell.attrs.bold,
            .dim = cell.attrs.dim,
            .italic = cell.attrs.italic,
            .reverse = cell.attrs.reverse,
            .invisible = cell.attrs.invisible,
            .underline = cell.attrs.underline,
            .strikethrough = cell.attrs.strikethrough,
        };
    }

    pub fn cellFont(cell: Cell) u8 {
        return cell.attrs.font;
    }

    pub fn cellBaseline(cell: Cell) u8 {
        return @backingInt(cell.attrs.baseline);
    }

    pub fn cellUnderlineStyle(cell: Cell) u8 {
        return @backingInt(cell.attrs.underline_style);
    }

    pub fn cellColor(cell: Cell, role: semantic.ColorRole) semantic.TextColor {
        const value = switch (role) {
            .foreground => cell.attrs.fg,
            .background => cell.attrs.bg,
            .underline_color => cell.attrs.underline_color,
        };
        return .{
            .kind = switch (value.colorKind()) {
                .default => .default,
                .indexed => .indexed,
                .rgb => .rgb,
            },
            .value = value.colorValue(),
        };
    }

    pub fn sameCellRendition(left: Cell, right: Cell) bool {
        return std.meta.eql(left.attrs, right.attrs);
    }

    pub fn isImagePlaceholder(_: *const Snapshot, _: usize, _: usize, sequence: []const u32) bool {
        // The adapter recognizes Kitty's reserved Unicode placeholder scalar;
        // the renderer itself remains unaware of that protocol encoding.
        return sequence.len != 0 and sequence[0] == kitty_image_placeholder;
    }

    pub fn graphics(snapshot: *const Snapshot) VT.Images {
        return snapshot.images;
    }

    pub fn observationRevision(_: *const Snapshot) u64 {
        return 0;
    }

    pub fn changedRowsBaseRevision(_: *const Snapshot) ?u64 {
        return null;
    }

    pub fn changedRows(_: *const Snapshot) ?[]const bool {
        return null;
    }

    pub fn rowShift(_: *const Snapshot) ?u16 {
        return null;
    }

    pub fn cursorShape(snapshot: *const Snapshot) semantic.CursorShape {
        return switch (snapshot.view.cursor_shape) {
            .block => .block,
            .underline => .underline,
            .bar => .bar,
            .none => .none,
        };
    }

    pub fn graphicsImageCount(state: VT.Images) usize {
        return state.imageCount();
    }

    pub fn graphicsImage(state: VT.Images, index: usize) semantic.Image {
        const value = state.image(index).?;
        return .{
            .image_id = value.id,
            .generation = value.generation,
            .width = value.width,
            .height = value.height,
        };
    }

    pub fn graphicsPlacementCount(state: VT.Images) usize {
        return state.placementCount();
    }

    pub fn graphicsPlacement(state: VT.Images, index: usize) ?semantic.ImagePlacement {
        const value = state.placement(index) orelse return null;
        return .{
            .image_id = value.image_id,
            .generation = value.generation,
            .row = value.row,
            .column = value.col,
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

    pub fn graphicsImageVisible(state: VT.Images, image_id: u32) bool {
        var index: usize = 0;
        while (index < state.placementCount()) : (index += 1) {
            const value = state.placement(index) orelse continue;
            if (value.image_id == image_id) return true;
        }
        return false;
    }
};
