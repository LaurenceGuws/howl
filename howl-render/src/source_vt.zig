//! Adapts a borrowed howl-vt observation to the terminal renderer source contract.
//!
//! The snapshot exists only for one synchronous projection call. No VT storage
//! or observation borrow survives the update.

const VT = @import("howl_vt").Terminal;
const semantic = @import("source");

const kitty_image_placeholder: u32 = 0x10eeee;

/// Implements the source-neutral renderer contract over one borrowed canonical VT cut.
pub const Source = struct {
    /// Copies small view/presentation handles for one synchronous projection.
    /// `images` and the SemanticView backing screen remain VT-borrowed until mutation.
    pub const Snapshot = struct {
        view: VT.SemanticView,
        colors: VT.Presentation,
        images: VT.Images,
    };

    /// Identifies one visible canonical VT row by its bounded numeric index.
    pub const Row = u16;
    /// Copies one canonical VT cell value while its extended scalar tail remains view-addressed.
    pub const Cell = VT.Cell;
    /// Copies the canonical terminal palette and dynamic presentation colors.
    pub const Presentation = VT.Presentation;
    /// Uses the canonical four-channel terminal color carried by Presentation.
    pub const PresentationColor = VT.Rgb;
    /// Borrows one coherent canonical image/placement observation.
    pub const Graphics = VT.Images;
    /// Direct VT observations expose no revision-relative changed-row contract.
    pub const supports_incremental = false;

    /// Returns the declared visible terminal row count.
    pub fn rows(snapshot: *const Snapshot) u16 {
        return snapshot.view.rows;
    }

    /// Returns the declared physical terminal column count.
    pub fn columns(snapshot: *const Snapshot) u16 {
        return snapshot.view.cols;
    }

    /// Returns the canonical cursor row in the current visible view.
    pub fn cursorRow(snapshot: *const Snapshot) u16 {
        return snapshot.view.cursor_row;
    }

    /// Returns the canonical cursor column in the current visible view.
    pub fn cursorColumn(snapshot: *const Snapshot) u16 {
        return snapshot.view.cursor_col;
    }

    /// Reports canonical cursor visibility before renderer surface clipping.
    pub fn cursorVisible(snapshot: *const Snapshot) bool {
        return snapshot.view.cursor_visible;
    }

    /// Borrows the presentation copy retained by this synchronous adapter snapshot.
    pub fn presentation(snapshot: *const Snapshot) *const VT.Presentation {
        return &snapshot.colors;
    }

    /// Returns the number of physically exposed row records for geometry validation.
    pub fn rowCount(snapshot: *const Snapshot) usize {
        return snapshot.view.rows;
    }

    /// Maps one validated dense row-record index to its canonical VT row identity.
    pub fn rowAt(_: *const Snapshot, index: usize) Row {
        return @intCast(index);
    }

    /// Returns the number of physically exposed cells for one canonical row.
    pub fn rowCellCount(snapshot: *const Snapshot, _: Row) usize {
        return snapshot.view.cols;
    }

    /// Copies one canonical cell at already-validated physical row/column coordinates.
    pub fn cellAt(snapshot: *const Snapshot, row: Row, column: usize) Cell {
        return snapshot.view.cellInfoAt(row, @intCast(column));
    }

    /// Normalizes one VT DEC line-geometry value into renderer-private semantics.
    pub fn lineGeometry(snapshot: *const Snapshot, row: Row) semantic.LineGeometry {
        return switch (snapshot.view.lineGeometry(row)) {
            .single_width => .single_width,
            .double_width => .double_width,
            .double_height_top => .double_height_top,
            .double_height_bottom => .double_height_bottom,
        };
    }

    /// Borrows/copies one lead cell's complete scalar cluster into caller scratch.
    /// Continuation and blank cells intentionally expose an empty sequence.
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

    /// Copies only rendition bits that directly affect this untimed frame projection.
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

    /// Returns the terminal font slot independently of VT's packed field width.
    pub fn cellFont(cell: Cell) u8 {
        return cell.attrs.font;
    }

    /// Returns the encoded baseline selector independently of VT's enum type.
    pub fn cellBaseline(cell: Cell) u8 {
        return @backingInt(cell.attrs.baseline);
    }

    /// Returns the encoded underline style independently of VT's enum type.
    pub fn cellUnderlineStyle(cell: Cell) u8 {
        return @backingInt(cell.attrs.underline_style);
    }

    /// Normalizes one requested cell color role without leaking VT color types.
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

    /// Recognizes Kitty's reserved Unicode placement scalar at the source boundary.
    pub fn isImagePlaceholder(_: *const Snapshot, _: usize, _: usize, sequence: []const u32) bool {
        // The adapter recognizes Kitty's reserved Unicode placeholder scalar;
        // the renderer itself remains unaware of that protocol encoding.
        return sequence.len != 0 and sequence[0] == kitty_image_placeholder;
    }

    /// Borrows the coherent VT image/placement view captured for this history cut.
    pub fn graphics(snapshot: *const Snapshot) VT.Images {
        return snapshot.images;
    }

    /// Normalizes canonical cursor geometry without carrying source enum identity.
    pub fn cursorShape(snapshot: *const Snapshot) semantic.CursorShape {
        return switch (snapshot.view.cursor_shape) {
            .block => .block,
            .underline => .underline,
            .bar => .bar,
            .none => .none,
        };
    }

    /// Returns every retained canonical image record, including currently hidden images.
    pub fn graphicsImageCount(state: VT.Images) usize {
        return state.imageCount();
    }

    /// Normalizes one retained VT image into renderer-private identity and extent.
    pub fn graphicsImage(state: VT.Images, index: usize) semantic.Image {
        const value = state.image(index).?;
        return .{
            .image_id = value.id,
            .generation = value.generation,
            .width = value.width,
            .height = value.height,
        };
    }

    /// Returns the bounded placement index space for this visible VT cut.
    pub fn graphicsPlacementCount(state: VT.Images) usize {
        return state.placementCount();
    }

    /// Copies one visible physical or virtual placement, skipping absent index slots.
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

    /// Reports whether any visible placement currently references one retained image.
    pub fn graphicsImageVisible(state: VT.Images, image_id: u32) bool {
        var index: usize = 0;
        while (index < state.placementCount()) : (index += 1) {
            const value = state.placement(index) orelse continue;
            if (value.image_id == image_id) return true;
        }
        return false;
    }
};
