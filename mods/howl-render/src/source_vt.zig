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
        revision: u64 = 0,
        changed_rows_base_revision: ?u64 = null,
        changed_rows: ?[]const bool = null,
    };

    /// Borrows a live row once per projection pass; history uses copied-cell fallback.
    pub const Row = struct { index: u16, cells: ?[]const VT.Cell };
    /// Borrows one canonical cell only for this synchronous projection.
    pub const Cell = *const VT.Cell;
    /// Owns fallback storage when a projected history row has no live cell slice.
    pub const CellScratch = VT.Cell;
    /// Copies the canonical terminal palette and dynamic presentation colors.
    pub const Presentation = VT.Presentation;
    /// Uses the canonical four-channel terminal color carried by Presentation.
    pub const PresentationColor = VT.Rgb;
    /// Borrows one coherent canonical image/placement observation.
    pub const Graphics = VT.Images;
    /// A synchronous owner may supply repairs from its non-consuming row identities.
    pub const supports_incremental = true;

    /// Returns the canonical content identity captured for these repairs.
    pub fn observationRevision(snapshot: *const Snapshot) u64 {
        return snapshot.revision;
    }

    /// Returns the clamped canonical viewport history offset.
    pub fn historyOffset(snapshot: *const Snapshot) u32 {
        return snapshot.view.history_offset;
    }

    /// Identifies the canonical active screen for repair provenance.
    pub fn alternateScreen(snapshot: *const Snapshot) bool {
        return snapshot.view.is_alternate_screen;
    }

    /// Returns the last complete source revision described by the repair hint.
    pub fn changedRowsBaseRevision(snapshot: *const Snapshot) ?u64 {
        return snapshot.changed_rows_base_revision;
    }

    /// Borrows synchronous owner-computed row repairs, or requests full projection.
    pub fn changedRows(snapshot: *const Snapshot) ?[]const bool {
        return snapshot.changed_rows;
    }

    /// Non-consuming BG-source identity for live ordinary rows. Global reverse
    /// makes foreground writes affect backgrounds and therefore uses full projection.
    pub fn rowBackgroundGeneration(snapshot: *const Snapshot, row: usize) ?u64 {
        if (snapshot.colors.reverse_screen) return null;
        return snapshot.view.rowBackgroundGeneration(@intCast(row));
    }

    /// Native repairs are position-relative and carry no scrolling translation.
    pub fn rowShift(_: *const Snapshot) ?u16 {
        return 0;
    }

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
    pub fn rowAt(snapshot: *const Snapshot, index: usize) Row {
        const row: u16 = @intCast(index);
        return .{ .index = row, .cells = snapshot.view.rowCells(row) };
    }

    /// Returns the number of physically exposed cells for one canonical row.
    pub fn rowCellCount(snapshot: *const Snapshot, row: Row) usize {
        return if (row.cells) |cells| cells.len else snapshot.view.cols;
    }

    /// Borrows a live cell or copies a history cell into caller-owned scratch.
    /// A history borrow lasts only until that scratch is reused.
    pub inline fn cellAt(snapshot: *const Snapshot, row: Row, column: usize, scratch: *CellScratch) Cell {
        if (row.cells) |cells| return &cells[column];
        scratch.* = @call(.always_inline, VT.SemanticView.cellInfoAt, .{ &snapshot.view, row.index, @as(u16, @intCast(column)) });
        return scratch;
    }

    /// Normalizes one VT DEC line-geometry value into renderer-private semantics.
    pub inline fn lineGeometry(snapshot: *const Snapshot, row: Row) semantic.LineGeometry {
        return switch (@call(.always_inline, VT.SemanticView.lineGeometry, .{ &snapshot.view, row.index })) {
            .single_width => .single_width,
            .double_width => .double_width,
            .double_height_top => .double_height_top,
            .double_height_bottom => .double_height_bottom,
        };
    }

    /// Borrows/copies one lead cell's complete scalar cluster into caller scratch.
    /// Continuation and blank cells intentionally expose an empty sequence.
    pub inline fn cellScalars(
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
        const sequence = @call(.always_inline, VT.SemanticView.cellScalarsAt, .{ &snapshot.view, @as(u16, @intCast(row)), @as(u16, @intCast(column)), &scalars });
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

test "native cell borrows keep independent history scratch and live storage separate" {
    const std = @import("std");
    var vt: VT = undefined;
    try VT.initWithHistoryInto(&vt, std.testing.allocator, 3, 12, 8);
    defer vt.deinit();
    // zig-audit: acknowledge discard
    // reason: Exact historical/live cells, the combining tail and unchanged canonical sequence are asserted below.
    _ = try vt.feed("A\xcc\x81B\r\nCD\r\nEF\r\nGH");
    const observation = vt.observation();
    const sequence = observation.contentSequence();
    const snapshot: Source.Snapshot = .{
        .view = observation.semanticView(1),
        .colors = observation.presentation(),
        .images = observation.images(1),
    };
    const history = Source.rowAt(&snapshot, 0);
    const live = Source.rowAt(&snapshot, 1);
    try std.testing.expect(history.cells == null);
    try std.testing.expect(live.cells != null);
    var first_scratch: Source.CellScratch = undefined;
    var second_scratch: Source.CellScratch = undefined;
    const first = Source.cellAt(&snapshot, history, 0, &first_scratch);
    const second = Source.cellAt(&snapshot, history, 1, &second_scratch);
    try std.testing.expectEqual(@as(u32, 'A'), first.codepoint);
    try std.testing.expectEqual(@as(u32, 'B'), second.codepoint);
    var scalars: [24]u32 = undefined;
    try std.testing.expectEqualSlices(u32, &.{ 'A', 0x301 }, Source.cellScalars(&snapshot, 0, 0, first, &scalars));
    const live_cell = Source.cellAt(&snapshot, live, 0, &first_scratch);
    // Reading history into the same fallback storage cannot overwrite the live borrow.
    try std.testing.expectEqual(@as(u32, 'B'), Source.cellAt(&snapshot, history, 1, &first_scratch).codepoint);
    try std.testing.expectEqual(@as(u32, 'C'), live_cell.codepoint);
    try std.testing.expectEqual(sequence, observation.contentSequence());
}
