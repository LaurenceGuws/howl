//! Owns retained blank/ASCII terminal cells and sparse backend lowering.
//!
//! The owner applies ordered cell, fill, full-row copy, replacement, and
//! static-cursor mutations to one current grid. Bounded first-old cell and row
//! baselines permit temporary mutations to cancel before backend work without
//! a second complete visual grid. Full-row copies
//! rotate physical row identity, so scrolling lowers to row indirection plus
//! exposed-row changes instead of moved-cell payloads.

const std = @import("std");
const howl_vt = @import("howl_vt");
const journal = howl_vt.render_journal;

/// Bounds one retained terminal pane independently of its row/column shape.
pub const maximum_cells: usize = 65_536;
const glyph_key_count: usize = 95 * 4;

/// Stores one final eight-bit RGB component triplet.
pub const Rgb = extern struct {
    /// Stores red intensity.
    r: u8,
    /// Stores green intensity.
    g: u8,
    /// Stores blue intensity.
    b: u8,
};

/// Stores the ordinary static style applied to one terminal cell.
pub const Style = packed struct(u8) {
    /// Selects the configured bold glyph tuple.
    bold: bool = false,
    /// Requests dim foreground presentation without changing glyph identity.
    dim: bool = false,
    /// Selects the configured italic glyph tuple.
    italic: bool = false,
    /// Draws one static underline with `Cell.underline_color`.
    underline: bool = false,
    /// Draws one static strike line.
    strikethrough: bool = false,
    /// Keeps the packed layout stable for later reviewed attributes.
    reserved: u3 = 0,
};

/// Stores one resolved blank or ASCII cell without palette or VT ownership.
pub const Cell = extern struct {
    /// Stores zero for blank, printable ASCII, or `?` for unsupported input.
    codepoint: u8,
    /// Stores final foreground color.
    foreground: Rgb,
    /// Stores final background color.
    background: Rgb,
    /// Stores final static underline color.
    underline_color: Rgb,
    /// Stores ordinary resolved style.
    style: Style = .{},

    /// Resolves unsupported codepoints deterministically to printable `?`.
    pub fn init(
        codepoint: u21,
        foreground: Rgb,
        background: Rgb,
        underline_color: Rgb,
        style: Style,
    ) Cell {
        var canonical_style = style;
        canonical_style.reserved = 0;
        return .{
            .codepoint = normalizeCodepoint(codepoint),
            .foreground = foreground,
            .background = background,
            .underline_color = underline_color,
            .style = canonical_style,
        };
    }

    /// Constructs a blank cell with resolved colors.
    pub fn blank(foreground: Rgb, background: Rgb) Cell {
        return init(0, foreground, background, foreground, .{});
    }
};

comptime {
    std.debug.assert(@sizeOf(Rgb) == 3);
    std.debug.assert(@alignOf(Rgb) == 1);
    std.debug.assert(@sizeOf(Cell) == 11);
    std.debug.assert(@alignOf(Cell) == 1);
    std.debug.assert(@sizeOf(Cell) == @sizeOf(journal.Cell));
    std.debug.assert(@alignOf(Cell) == @alignOf(journal.Cell));
}

/// Selects one static cursor shape.
pub const CursorShape = enum(u8) { block, underline, bar, hidden };

/// Stores one resolved static cursor independently from terminal cells.
pub const Cursor = extern struct {
    /// Selects the logical cursor row.
    row: u16 = 0,
    /// Selects the logical cursor column.
    col: u16 = 0,
    /// Stores cursor fill color.
    color: Rgb = .{ .r = 0, .g = 0, .b = 0 },
    /// Stores text color used beneath a visible block cursor.
    text_color: Rgb = .{ .r = 0, .g = 0, .b = 0 },
    /// Selects block, underline, bar, or canonical hidden state.
    shape: CursorShape = .hidden,
    /// Reports whether cursor geometry contributes to a draw.
    visible: bool = false,
};

comptime {
    std.debug.assert(@sizeOf(Cursor) == 12);
    std.debug.assert(@alignOf(Cursor) == 2);
}

/// Identifies the raster identity required by one printable ASCII cell.
pub const GlyphKey = packed struct(u16) {
    /// Stores printable ASCII U+0020 through U+007E.
    codepoint: u7,
    /// Selects the bold raster tuple.
    bold: bool,
    /// Selects the italic raster tuple.
    italic: bool,
    /// Preserves exact key representation.
    reserved: u7 = 0,
};

/// Rotates one contiguous logical-row range over retained physical rows.
pub const RowRotation = struct {
    /// Identifies the first logical row in the rotation.
    first: u16,
    /// Bounds the contiguous logical rows in the rotation.
    count: u16,
    /// Negative rotates toward lower logical rows; positive rotates upward.
    shift: i16,
};

/// Fills one contiguous physical-cell span with one resolved cell.
pub const FillUpdate = struct {
    /// Identifies the first persistent physical cell.
    first: u32,
    /// Bounds the contiguous physical cells.
    count: u32,
    /// Supplies the final repeated cell.
    cell: Cell,
};

/// Replaces one exact physical cell.
pub const CellUpdate = struct {
    /// Identifies one persistent physical cell.
    physical_index: u32,
    /// Supplies its final value.
    cell: Cell,
};

/// Selects the only complete-grid replacement entry points.
pub const ReplacementKind = enum { initialization, resize, alternate_grid };

/// Borrows the complete initial/resize/alternate-grid replacement.
pub const Replacement = struct {
    /// Names the only three complete-grid entry points.
    kind: ReplacementKind,
    /// Supplies nonzero logical rows.
    rows: u16,
    /// Supplies nonzero logical columns.
    cols: u16,
    /// Borrows complete row-major cells.
    cells: []const Cell,
};

/// Borrows exact sparse work until `Grid.complete` or `Grid.discard`.
pub const Update = struct {
    /// Supplies active logical rows.
    rows: u16,
    /// Supplies active logical columns.
    cols: u16,
    /// Borrows complete state only for init, resize, or grid replacement.
    replacement: ?Replacement,
    /// Borrows ordered row-indirection changes.
    row_rotations: []const RowRotation,
    /// Borrows final structured fills.
    fills: []const FillUpdate,
    /// Borrows final individual cell changes not covered by fills.
    cells: []const CellUpdate,
    /// Borrows unique raster identities required by this update.
    glyphs: []const GlyphKey,
    /// Supplies a changed cursor or null when accepted cursor state remains.
    cursor: ?Cursor,
};

/// Fixes all retained and candidate storage at construction.
pub const Limits = struct {
    /// Bounds logical and physical rows.
    rows: u16,
    /// Bounds logical and physical columns.
    cols: u16,
    /// Bounds retained row-copy and fill descriptions.
    structured_operations: usize,
    /// Bounds individual final cell updates.
    sparse_cell_updates: usize,
};

/// Returns exact retained CPU bytes requested by one Grid configuration.
/// Allocator metadata and alignment padding outside requested slices are not
/// owned by Grid and are therefore excluded.
pub fn retainedCpuBytes(limits: Limits) Error!usize {
    const cells = try validateLimits(limits, 1, 1);
    const rows: usize = limits.rows;
    const sparse = limits.sparse_cell_updates;
    const structured = limits.structured_operations;
    var total: usize = @sizeOf(Grid);
    inline for (.{
        cells * @sizeOf(Cell),
        rows * @sizeOf(u16),
        rows * @sizeOf(u16),
        cells * @sizeOf(u32),
        sparse * @sizeOf(TouchedCell),
        rows * @sizeOf(u16),
        ((rows + 63) / 64) * @sizeOf(u64),
        rows * @sizeOf(u16),
        structured * @sizeOf(FillHint),
        rows * @sizeOf(RowRotation),
        structured * @sizeOf(FillUpdate),
        sparse * @sizeOf(CellUpdate),
        sparse * @sizeOf(bool),
        glyph_key_count * @sizeOf(GlyphKey),
    }) |bytes| total = std.math.add(usize, total, bytes) catch return error.InvalidLimits;
    return total;
}

/// Reports exact construction, geometry, capacity, or candidate ownership.
pub const Error = error{
    InvalidLimits,
    InvalidGeometry,
    InvalidIdentity,
    SparseUpdateLimit,
    CandidatePending,
    NoCandidate,
    OutOfMemory,
};

fn journalRgb(value: journal.Rgb) Rgb {
    return .{ .r = value.r, .g = value.g, .b = value.b };
}

fn journalStyle(value: journal.Style) Style {
    return .{
        .bold = value.bold,
        .dim = value.dim,
        .italic = value.italic,
        .underline = value.underline,
        .strikethrough = value.strikethrough,
    };
}

fn journalCell(value: journal.Cell) Cell {
    return .{
        .codepoint = value.codepoint,
        .foreground = journalRgb(value.foreground),
        .background = journalRgb(value.background),
        .underline_color = journalRgb(value.underline_color),
        .style = journalStyle(value.style),
    };
}

fn journalCursor(value: journal.Cursor) Cursor {
    return .{
        .row = value.row,
        .col = value.col,
        .color = journalRgb(value.color),
        .text_color = journalRgb(value.text_color),
        .shape = switch (value.shape) {
            .block => .block,
            .underline => .underline,
            .bar => .bar,
            .hidden => .hidden,
        },
        .visible = value.visible,
    };
}

/// Applies one complete VT-owned mutation transaction in source order.
///
/// The transaction already contains final visual values. This boundary does
/// not interpret parser, palette, protection, or terminal attribute semantics.
pub fn applyTransaction(grid: *Grid, transaction: journal.Transaction) Error!void {
    for (transaction.operations) |operation| switch (operation) {
        .set_cells => |set| {
            for (set.cells, 0..) |cell, offset|
                try grid.set(set.row, set.col + @as(u16, @intCast(offset)), journalCell(cell));
        },
        .fill => |fill| try grid.fill(
            fill.rect.row,
            fill.rect.col,
            fill.rect.rows,
            fill.rect.cols,
            journalCell(fill.cell),
        ),
        .copy => |copy| try grid.copyRect(
            copy.source.row,
            copy.source.col,
            copy.source.rows,
            copy.source.cols,
            copy.destination_row,
            copy.destination_col,
        ),
        .masked_fill => |fill| try grid.maskedFill(
            fill.rect.row,
            fill.rect.col,
            fill.rect.rows,
            fill.rect.cols,
            fill.mask,
            journalCell(fill.cell),
        ),
        .recolor => |recolor| {
            var rgb: [256]Rgb = undefined;
            for (&rgb, recolor.rgb) |*destination, source|
                destination.* = journalRgb(source);
            try grid.recolor(
                recolor.foreground,
                recolor.background,
                recolor.underline,
                &rgb,
            );
        },
        .visual_patch => |patch| try grid.visualPatch(
            patch.rect.row,
            patch.rect.col,
            patch.rect.rows,
            patch.rect.cols,
            patch.changed_mask,
            journalStyle(patch.set_style),
            journalStyle(patch.clear_style),
            journalStyle(patch.toggle_style),
            patch.swap_foreground_background,
            if (patch.foreground) |value| journalRgb(value) else null,
            if (patch.background) |value| journalRgb(value) else null,
            if (patch.underline) |value| journalRgb(value) else null,
        ),
        .replace => |replacement| {
            const count = std.math.mul(usize, replacement.rows, replacement.cols) catch
                return error.InvalidGeometry;
            if (replacement.cells.len != count or count > maximum_cells)
                return error.InvalidGeometry;
            const cells = @as(
                [*]const Cell,
                @ptrCast(replacement.cells.ptr),
            )[0..count];
            try grid.replace(
                switch (replacement.kind) {
                    .initialization => .initialization,
                    .resize => .resize,
                    .alternate => .alternate_grid,
                },
                replacement.rows,
                replacement.cols,
                cells,
            );
        },
        .cursor => |cursor| try grid.setCursor(journalCursor(cursor)),
    };
}

const FillHint = struct {
    first: usize,
    count: usize,
    cell: Cell,
};

const TouchedCell = struct {
    physical_index: u32,
    baseline: Cell,
};

const untracked_cell = std.math.maxInt(u32);

/// Retains one current terminal grid and bounded sparse baselines with no
/// post-init allocation in ordinary mutation, lowering, completion, or discard.
pub const Grid = struct {
    allocator: std.mem.Allocator,
    limits: Limits,
    rows: u16,
    cols: u16,
    rendered_rows: u16,
    rendered_cols: u16,
    current_cells: []Cell,
    current_row_map: []u16,
    row_work: []u16,
    cell_slots: []u32,
    touched_cells: []TouchedCell,
    touched_cell_count: usize = 0,
    dirty_count: usize = 0,
    row_baselines: []u16,
    row_tracked_words: []u64,
    touched_rows: []u16,
    touched_row_count: usize = 0,
    row_dirty_count: usize = 0,
    fill_hints: []FillHint,
    fill_hint_count: usize = 0,
    candidate_rows: []RowRotation,
    candidate_row_count: usize = 0,
    candidate_fills: []FillUpdate,
    candidate_fill_count: usize = 0,
    candidate_cells: []CellUpdate,
    candidate_cell_count: usize = 0,
    candidate_covered: []bool,
    candidate_glyphs: []GlyphKey,
    candidate_glyph_count: usize = 0,
    current_cursor: Cursor = .{},
    rendered_cursor: Cursor = .{},
    rendered_valid: bool = false,
    replacement_pending: bool = true,
    replacement_kind: ReplacementKind = .initialization,
    candidate_pending: bool = false,

    /// Allocates one current grid, bounded baselines, and candidate storage.
    pub fn init(
        allocator: std.mem.Allocator,
        limits: Limits,
        rows: u16,
        cols: u16,
        initial: Cell,
    ) Error!Grid {
        const retained_cell_count = try validateLimits(limits, rows, cols);
        try validateCell(initial);
        const row_words = (@as(usize, limits.rows) + 63) / 64;
        const current_cells = allocator.alloc(Cell, retained_cell_count) catch return error.OutOfMemory;
        errdefer allocator.free(current_cells);
        const current_row_map = allocator.alloc(u16, limits.rows) catch return error.OutOfMemory;
        errdefer allocator.free(current_row_map);
        const row_work = allocator.alloc(u16, limits.rows) catch return error.OutOfMemory;
        errdefer allocator.free(row_work);
        const cell_slots = allocator.alloc(u32, retained_cell_count) catch return error.OutOfMemory;
        errdefer allocator.free(cell_slots);
        const touched_cells = allocator.alloc(TouchedCell, limits.sparse_cell_updates) catch return error.OutOfMemory;
        errdefer allocator.free(touched_cells);
        const row_baselines = allocator.alloc(u16, limits.rows) catch return error.OutOfMemory;
        errdefer allocator.free(row_baselines);
        const row_tracked_words = allocator.alloc(u64, row_words) catch return error.OutOfMemory;
        errdefer allocator.free(row_tracked_words);
        const touched_rows = allocator.alloc(u16, limits.rows) catch return error.OutOfMemory;
        errdefer allocator.free(touched_rows);
        const fill_hints = allocator.alloc(FillHint, limits.structured_operations) catch return error.OutOfMemory;
        errdefer allocator.free(fill_hints);
        const candidate_rows = allocator.alloc(RowRotation, limits.rows) catch return error.OutOfMemory;
        errdefer allocator.free(candidate_rows);
        const candidate_fills = allocator.alloc(FillUpdate, limits.structured_operations) catch return error.OutOfMemory;
        errdefer allocator.free(candidate_fills);
        const candidate_cells = allocator.alloc(CellUpdate, limits.sparse_cell_updates) catch return error.OutOfMemory;
        errdefer allocator.free(candidate_cells);
        const candidate_covered = allocator.alloc(bool, limits.sparse_cell_updates) catch return error.OutOfMemory;
        errdefer allocator.free(candidate_covered);
        const candidate_glyphs = allocator.alloc(GlyphKey, glyph_key_count) catch return error.OutOfMemory;
        errdefer allocator.free(candidate_glyphs);

        @memset(current_cells, initial);
        @memset(cell_slots, untracked_cell);
        @memset(row_tracked_words, 0);
        for (current_row_map, 0..) |*row, index| row.* = @intCast(index);
        return .{
            .allocator = allocator,
            .limits = limits,
            .rows = rows,
            .cols = cols,
            .rendered_rows = rows,
            .rendered_cols = cols,
            .current_cells = current_cells,
            .current_row_map = current_row_map,
            .row_work = row_work,
            .cell_slots = cell_slots,
            .touched_cells = touched_cells,
            .row_baselines = row_baselines,
            .row_tracked_words = row_tracked_words,
            .touched_rows = touched_rows,
            .fill_hints = fill_hints,
            .candidate_rows = candidate_rows,
            .candidate_fills = candidate_fills,
            .candidate_cells = candidate_cells,
            .candidate_covered = candidate_covered,
            .candidate_glyphs = candidate_glyphs,
        };
    }

    /// Releases every fixed allocation in reverse construction order.
    pub fn deinit(self: *Grid) void {
        self.allocator.free(self.candidate_glyphs);
        self.allocator.free(self.candidate_covered);
        self.allocator.free(self.candidate_cells);
        self.allocator.free(self.candidate_fills);
        self.allocator.free(self.candidate_rows);
        self.allocator.free(self.fill_hints);
        self.allocator.free(self.touched_rows);
        self.allocator.free(self.row_tracked_words);
        self.allocator.free(self.row_baselines);
        self.allocator.free(self.touched_cells);
        self.allocator.free(self.cell_slots);
        self.allocator.free(self.row_work);
        self.allocator.free(self.current_row_map);
        self.allocator.free(self.current_cells);
        self.* = undefined;
    }

    /// Returns one current logical cell for owner-level inspection.
    pub fn current(self: *const Grid, row: u16, col: u16) Error!Cell {
        return self.current_cells[try self.physicalIndex(row, col)];
    }

    /// Applies one resolved cell in global mutation order.
    pub fn set(self: *Grid, row: u16, col: u16, cell: Cell) Error!void {
        try self.requireMutable();
        try validateCell(cell);
        const index = try self.physicalIndex(row, col);
        try self.applyCell(index, cell);
    }

    /// Applies one resolved rectangular fill without allocating.
    pub fn fill(
        self: *Grid,
        row: u16,
        col: u16,
        row_count: u16,
        col_count: u16,
        cell: Cell,
    ) Error!void {
        try self.requireMutable();
        try validateCell(cell);
        if (row_count == 0 or col_count == 0 or
            @as(usize, row) + row_count > self.rows or
            @as(usize, col) + col_count > self.cols)
            return error.InvalidGeometry;
        const retain_hints = row_count <= self.fill_hints.len;
        if (retain_hints and self.fill_hint_count + row_count > self.fill_hints.len)
            self.fill_hint_count = 0;
        if (!self.replacement_pending and self.rendered_valid) {
            var additional: usize = 0;
            var preflight_row: u16 = 0;
            while (preflight_row < row_count) : (preflight_row += 1) {
                const first = try self.physicalIndex(row + preflight_row, col);
                for (first..first + col_count) |index| {
                    if (self.cell_slots[index] == untracked_cell and
                        !std.meta.eql(self.current_cells[index], cell))
                        additional += 1;
                }
            }
            if (additional > self.touched_cells.len - self.touched_cell_count)
                return error.SparseUpdateLimit;
        }
        var row_offset: u16 = 0;
        while (row_offset < row_count) : (row_offset += 1) {
            const first = try self.physicalIndex(row + row_offset, col);
            if (retain_hints) {
                self.fill_hints[self.fill_hint_count] = .{
                    .first = first,
                    .count = col_count,
                    .cell = cell,
                };
                self.fill_hint_count += 1;
            }
            for (first..first + col_count) |index| try self.applyCell(index, cell);
        }
    }

    /// Applies one overlapping full-row copy by rotating physical row identity.
    pub fn copyRows(
        self: *Grid,
        source_first: u16,
        destination_first: u16,
        count: u16,
    ) Error!void {
        try self.requireMutable();
        if (count == 0 or source_first == destination_first or
            @as(usize, source_first) + count > self.rows or
            @as(usize, destination_first) + count > self.rows)
            return error.InvalidGeometry;
        const distance = if (source_first > destination_first)
            source_first - destination_first
        else
            destination_first - source_first;
        if (distance > count) return error.InvalidGeometry;
        const first = @min(source_first, destination_first);
        const region_count = count + distance;
        self.trackRows(first, region_count);
        self.removeRowDifferences(first, region_count);
        @memcpy(self.row_work[0..region_count], self.current_row_map[first .. first + region_count]);
        const signed_shift: i16 = if (source_first > destination_first)
            -@as(i16, @intCast(distance))
        else
            @intCast(distance);
        rotateRows(self.current_row_map[first .. first + region_count], self.row_work[0..region_count], signed_shift);
        self.addRowDifferences(first, region_count);
    }

    /// Applies one overlapping rectangular copy in logical terminal order.
    pub fn copyRect(
        self: *Grid,
        source_row: u16,
        source_col: u16,
        row_count: u16,
        col_count: u16,
        destination_row: u16,
        destination_col: u16,
    ) Error!void {
        try self.requireMutable();
        if (row_count == 0 or col_count == 0 or
            @as(usize, source_row) + row_count > self.rows or
            @as(usize, destination_row) + row_count > self.rows or
            @as(usize, source_col) + col_count > self.cols or
            @as(usize, destination_col) + col_count > self.cols)
            return error.InvalidGeometry;
        if (source_col == 0 and destination_col == 0 and
            col_count == self.cols and source_row != destination_row)
            return self.copyRows(source_row, destination_row, row_count);

        var additional: usize = 0;
        for (0..row_count) |row_offset| for (0..col_count) |col_offset| {
            const index = try self.physicalIndex(
                destination_row + @as(u16, @intCast(row_offset)),
                destination_col + @as(u16, @intCast(col_offset)),
            );
            if (self.cell_slots[index] == untracked_cell) additional += 1;
        };
        if (!self.replacement_pending and self.rendered_valid and
            additional > self.touched_cells.len - self.touched_cell_count)
            return error.SparseUpdateLimit;

        const reverse = destination_row > source_row or
            (destination_row == source_row and destination_col > source_col);
        const total: usize = @as(usize, row_count) * col_count;
        for (0..total) |step| {
            const logical = if (reverse) total - 1 - step else step;
            const row_offset: u16 = @intCast(logical / col_count);
            const col_offset: u16 = @intCast(logical % col_count);
            const source = try self.physicalIndex(source_row + row_offset, source_col + col_offset);
            const destination = try self.physicalIndex(destination_row + row_offset, destination_col + col_offset);
            try self.applyCell(destination, self.current_cells[source]);
        }
    }

    /// Applies one VT-selected erase mask without interpreting protection.
    pub fn maskedFill(
        self: *Grid,
        row: u16,
        col: u16,
        row_count: u16,
        col_count: u16,
        mask: []const u8,
        cell: Cell,
    ) Error!void {
        try self.requireMutable();
        try validateCell(cell);
        const total = std.math.mul(usize, row_count, col_count) catch return error.InvalidGeometry;
        const mask_bytes = std.math.divCeil(usize, total, 8) catch return error.InvalidGeometry;
        if (row_count == 0 or col_count == 0 or
            @as(usize, row) + row_count > self.rows or
            @as(usize, col) + col_count > self.cols or
            mask.len != mask_bytes)
            return error.InvalidGeometry;
        var additional: usize = 0;
        for (0..total) |offset| {
            if (mask[offset / 8] & (@as(u8, 1) << @intCast(offset % 8)) == 0) continue;
            const index = try self.physicalIndex(row + @as(u16, @intCast(offset / col_count)), col + @as(u16, @intCast(offset % col_count)));
            if (self.cell_slots[index] == untracked_cell and !std.meta.eql(self.current_cells[index], cell)) additional += 1;
        }
        if (!self.replacement_pending and self.rendered_valid and
            additional > self.touched_cells.len - self.touched_cell_count)
            return error.SparseUpdateLimit;
        for (0..total) |offset| {
            if (mask[offset / 8] & (@as(u8, 1) << @intCast(offset % 8)) == 0) continue;
            const index = try self.physicalIndex(row + @as(u16, @intCast(offset / col_count)), col + @as(u16, @intCast(offset % col_count)));
            try self.applyCell(index, cell);
        }
    }

    /// Applies final VT-classified RGB channels without retaining provenance.
    pub fn recolor(
        self: *Grid,
        foreground: []const u8,
        background: []const u8,
        underline: []const u8,
        rgb: *const [256]Rgb,
    ) Error!void {
        try self.requireMutable();
        const count = try cellCount(self.rows, self.cols);
        if (foreground.len != count or background.len != count or underline.len != count)
            return error.InvalidGeometry;
        var additional: usize = 0;
        for (0..count) |logical| {
            if (foreground[logical] == 0 and background[logical] == 0 and underline[logical] == 0) continue;
            const row: u16 = @intCast(logical / self.cols);
            const col: u16 = @intCast(logical % self.cols);
            const index = try self.physicalIndex(row, col);
            if (self.cell_slots[index] == untracked_cell) additional += 1;
        }
        if (!self.replacement_pending and self.rendered_valid and
            additional > self.touched_cells.len - self.touched_cell_count)
            return error.SparseUpdateLimit;
        for (0..count) |logical| {
            const fg = foreground[logical];
            const bg = background[logical];
            const ul = underline[logical];
            if (fg == 0 and bg == 0 and ul == 0) continue;
            const row: u16 = @intCast(logical / self.cols);
            const col: u16 = @intCast(logical % self.cols);
            const index = try self.physicalIndex(row, col);
            var cell = self.current_cells[index];
            if (fg != 0) cell.foreground = rgb[fg];
            if (bg != 0) cell.background = rgb[bg];
            if (ul != 0) cell.underline_color = rgb[ul];
            try self.applyCell(index, cell);
        }
    }

    /// Applies one VT-resolved visual patch without interpreting terminal semantics.
    pub fn visualPatch(
        self: *Grid,
        row: u16,
        col: u16,
        row_count: u16,
        col_count: u16,
        changed_mask: ?[]const u8,
        set_style: Style,
        clear_style: Style,
        toggle_style: Style,
        swap_foreground_background: bool,
        foreground: ?Rgb,
        background: ?Rgb,
        underline: ?Rgb,
    ) Error!void {
        try self.requireMutable();
        if (set_style.reserved != 0 or clear_style.reserved != 0 or toggle_style.reserved != 0)
            return error.InvalidIdentity;
        const total = std.math.mul(usize, row_count, col_count) catch return error.InvalidGeometry;
        const mask_bytes = std.math.divCeil(usize, total, 8) catch return error.InvalidGeometry;
        if (row_count == 0 or col_count == 0 or
            @as(usize, row) + row_count > self.rows or
            @as(usize, col) + col_count > self.cols or
            (changed_mask != null and changed_mask.?.len != mask_bytes))
            return error.InvalidGeometry;

        var additional: usize = 0;
        for (0..total) |offset| {
            if (changed_mask) |mask|
                if (mask[offset / 8] & (@as(u8, 1) << @intCast(offset % 8)) == 0) continue;
            const index = try self.physicalIndex(row + @as(u16, @intCast(offset / col_count)), col + @as(u16, @intCast(offset % col_count)));
            if (self.cell_slots[index] == untracked_cell) additional += 1;
        }
        if (!self.replacement_pending and self.rendered_valid and
            additional > self.touched_cells.len - self.touched_cell_count)
            return error.SparseUpdateLimit;

        const set_bits: u8 = @bitCast(set_style);
        const clear_bits: u8 = @bitCast(clear_style);
        const toggle_bits: u8 = @bitCast(toggle_style);
        for (0..total) |offset| {
            if (changed_mask) |mask|
                if (mask[offset / 8] & (@as(u8, 1) << @intCast(offset % 8)) == 0) continue;
            const index = try self.physicalIndex(row + @as(u16, @intCast(offset / col_count)), col + @as(u16, @intCast(offset % col_count)));
            var cell = self.current_cells[index];
            var style_bits: u8 = @bitCast(cell.style);
            style_bits = ((style_bits | set_bits) & ~clear_bits) ^ toggle_bits;
            cell.style = @bitCast(style_bits & 0x1f);
            if (swap_foreground_background)
                std.mem.swap(Rgb, &cell.foreground, &cell.background);
            if (foreground) |value| cell.foreground = value;
            if (background) |value| cell.background = value;
            if (underline) |value| cell.underline_color = value;
            try self.applyCell(index, cell);
        }
    }

    /// Replaces the complete grid for init, resize, or alternate-screen state.
    pub fn replace(
        self: *Grid,
        kind: ReplacementKind,
        rows: u16,
        cols: u16,
        cells: []const Cell,
    ) Error!void {
        try self.requireMutable();
        const count = try validateDimensions(self.limits, rows, cols);
        if (kind == .initialization and
            (self.rendered_valid or !self.replacement_pending or
                rows != self.rows or cols != self.cols))
            return error.InvalidGeometry;
        if (cells.len != count) return error.InvalidGeometry;
        for (cells) |cell| try validateCell(cell);
        self.clearMutationTracking();
        @memcpy(self.current_cells[0..count], cells);
        for (self.current_row_map, 0..) |*entry, index| entry.* = @intCast(index);
        self.rows = rows;
        self.cols = cols;
        self.replacement_pending = true;
        self.replacement_kind = kind;
    }

    /// Replaces the complete static cursor after exact geometry validation.
    pub fn setCursor(self: *Grid, cursor: Cursor) Error!void {
        try self.requireMutable();
        try validateCursor(cursor, self.rows, self.cols);
        self.current_cursor = if (cursor.visible) cursor else .{};
    }

    /// Lowers final differences only. `null` means no terminal GPU work.
    pub fn prepare(self: *Grid) Error!?Update {
        if (self.candidate_pending) return error.CandidatePending;
        self.resetCandidate();
        try validateCursor(self.current_cursor, self.rows, self.cols);
        if (self.replacement_pending or !self.rendered_valid or
            self.rows != self.rendered_rows or self.cols != self.rendered_cols)
        {
            const count = try cellCount(self.rows, self.cols);
            for (self.current_cells[0..count]) |cell| try self.appendGlyph(cell);
            self.candidate_pending = true;
            return .{
                .rows = self.rows,
                .cols = self.cols,
                .replacement = .{
                    .kind = self.replacement_kind,
                    .rows = self.rows,
                    .cols = self.cols,
                    .cells = self.current_cells[0..count],
                },
                .row_rotations = &.{},
                .fills = &.{},
                .cells = &.{},
                .glyphs = self.candidate_glyphs[0..self.candidate_glyph_count],
                .cursor = self.current_cursor,
            };
        }

        const rows_changed = self.row_dirty_count != 0;
        const cursor_changed = !std.meta.eql(self.current_cursor, self.rendered_cursor);
        if (self.dirty_count == 0 and !rows_changed and !cursor_changed) {
            self.clearMutationTracking();
            return null;
        }

        if (rows_changed) {
            self.deriveRowRotations();
        }
        @memset(self.candidate_covered[0..self.touched_cell_count], false);
        var hint_index = self.fill_hint_count;
        while (hint_index > 0) {
            hint_index -= 1;
            const hint = self.fill_hints[hint_index];
            if (!self.fillContributes(hint)) continue;
            std.debug.assert(self.candidate_fill_count < self.candidate_fills.len);
            self.candidate_fills[self.candidate_fill_count] = .{
                .first = @intCast(hint.first),
                .count = @intCast(hint.count),
                .cell = hint.cell,
            };
            self.candidate_fill_count += 1;
            for (hint.first..hint.first + hint.count) |index| {
                const slot = self.cell_slots[index];
                std.debug.assert(slot != untracked_cell);
                self.candidate_covered[slot] = true;
            }
            try self.appendGlyph(hint.cell);
        }
        for (self.touched_cells[0..self.touched_cell_count], 0..) |touched, slot| {
            const index: usize = @intCast(touched.physical_index);
            if (std.meta.eql(self.current_cells[index], touched.baseline) or
                self.candidate_covered[slot])
                continue;
            if (self.candidate_cell_count == self.candidate_cells.len)
                return error.SparseUpdateLimit;
            const cell = self.current_cells[index];
            self.candidate_cells[self.candidate_cell_count] = .{
                .physical_index = @intCast(index),
                .cell = cell,
            };
            self.candidate_cell_count += 1;
            try self.appendGlyph(cell);
        }
        self.candidate_pending = true;
        return .{
            .rows = self.rows,
            .cols = self.cols,
            .replacement = null,
            .row_rotations = self.candidate_rows[0..self.candidate_row_count],
            .fills = self.candidate_fills[0..self.candidate_fill_count],
            .cells = self.candidate_cells[0..self.candidate_cell_count],
            .glyphs = self.candidate_glyphs[0..self.candidate_glyph_count],
            .cursor = if (cursor_changed) self.current_cursor else null,
        };
    }

    /// Accepts exactly the prepared update without scanning unchanged cells.
    pub fn complete(self: *Grid) Error!void {
        if (!self.candidate_pending) return error.NoCandidate;
        if (self.replacement_pending or !self.rendered_valid or
            self.rows != self.rendered_rows or self.cols != self.rendered_cols)
        {
            self.rendered_rows = self.rows;
            self.rendered_cols = self.cols;
            self.rendered_valid = true;
            self.replacement_pending = false;
        }
        self.rendered_cursor = self.current_cursor;
        self.candidate_pending = false;
        self.clearMutationTracking();
        self.resetCandidate();
    }

    /// Discards candidate borrowing while preserving current and accepted baseline ownership.
    pub fn discard(self: *Grid) Error!void {
        if (!self.candidate_pending) return error.NoCandidate;
        self.candidate_pending = false;
        self.resetCandidate();
    }

    fn requireMutable(self: *const Grid) Error!void {
        if (self.candidate_pending) return error.CandidatePending;
    }

    fn physicalIndex(self: *const Grid, row: u16, col: u16) Error!usize {
        if (row >= self.rows or col >= self.cols) return error.InvalidGeometry;
        return @as(usize, self.current_row_map[row]) * self.cols + col;
    }

    fn applyCell(self: *Grid, index: usize, cell: Cell) Error!void {
        if (std.meta.eql(self.current_cells[index], cell)) return;
        if (self.replacement_pending or !self.rendered_valid) {
            self.current_cells[index] = cell;
            return;
        }
        var slot = self.cell_slots[index];
        if (slot == untracked_cell) {
            if (self.touched_cell_count == self.touched_cells.len)
                return error.SparseUpdateLimit;
            slot = @intCast(self.touched_cell_count);
            self.cell_slots[index] = slot;
            self.touched_cells[self.touched_cell_count] = .{
                .physical_index = @intCast(index),
                .baseline = self.current_cells[index],
            };
            self.touched_cell_count += 1;
        }
        const touched = self.touched_cells[slot];
        const was_dirty = !std.meta.eql(self.current_cells[index], touched.baseline);
        self.current_cells[index] = cell;
        const is_dirty = !std.meta.eql(cell, touched.baseline);
        if (was_dirty != is_dirty) {
            if (is_dirty)
                self.dirty_count += 1
            else
                self.dirty_count -= 1;
        }
    }

    fn trackRows(self: *Grid, first: u16, count: u16) void {
        if (self.replacement_pending or !self.rendered_valid) return;
        for (first..first + count) |row| {
            if (bit(self.row_tracked_words, row)) continue;
            setBit(self.row_tracked_words, row, true);
            self.row_baselines[row] = self.current_row_map[row];
            self.touched_rows[self.touched_row_count] = @intCast(row);
            self.touched_row_count += 1;
        }
    }

    fn removeRowDifferences(self: *Grid, first: u16, count: u16) void {
        if (self.replacement_pending or !self.rendered_valid) return;
        for (first..first + count) |row| {
            if (self.current_row_map[row] != self.row_baselines[row])
                self.row_dirty_count -= 1;
        }
    }

    fn addRowDifferences(self: *Grid, first: u16, count: u16) void {
        if (self.replacement_pending or !self.rendered_valid) return;
        for (first..first + count) |row| {
            if (self.current_row_map[row] != self.row_baselines[row])
                self.row_dirty_count += 1;
        }
    }

    fn fillContributes(self: *const Grid, hint: FillHint) bool {
        for (hint.first..hint.first + hint.count) |index| {
            const slot = self.cell_slots[index];
            if (!std.meta.eql(self.current_cells[index], hint.cell) or
                slot == untracked_cell or
                std.meta.eql(self.current_cells[index], self.touched_cells[slot].baseline) or
                self.candidate_covered[slot])
                return false;
        }
        return true;
    }

    fn appendGlyph(self: *Grid, cell: Cell) Error!void {
        if (cell.codepoint == 0 or cell.codepoint == ' ') return;
        const key = GlyphKey{
            .codepoint = @intCast(cell.codepoint),
            .bold = cell.style.bold,
            .italic = cell.style.italic,
        };
        for (self.candidate_glyphs[0..self.candidate_glyph_count]) |existing|
            if (existing == key) return;
        if (self.candidate_glyph_count == self.candidate_glyphs.len)
            return error.SparseUpdateLimit;
        self.candidate_glyphs[self.candidate_glyph_count] = key;
        self.candidate_glyph_count += 1;
    }

    fn deriveRowRotations(self: *Grid) void {
        std.debug.assert(self.candidate_rows.len >= self.rows);
        for (self.row_work[0..self.rows], 0..) |*row, logical| {
            row.* = if (bit(self.row_tracked_words, logical))
                self.row_baselines[logical]
            else
                self.current_row_map[logical];
        }
        var first: usize = 0;
        while (first < self.rows and self.row_work[first] == self.current_row_map[first])
            first += 1;
        if (first == self.rows) return;
        var last: usize = self.rows - 1;
        while (self.row_work[last] == self.current_row_map[last]) last -= 1;
        const rotation_count = last - first + 1;
        var source_offset: usize = 1;
        while (self.row_work[first + source_offset] != self.current_row_map[first])
            source_offset += 1;
        var exact_rotation = true;
        for (0..rotation_count) |offset| {
            if (self.current_row_map[first + offset] !=
                self.row_work[first + (offset + source_offset) % rotation_count])
            {
                exact_rotation = false;
                break;
            }
        }
        if (exact_rotation) {
            self.candidate_rows[0] = .{
                .first = @intCast(first),
                .count = @intCast(rotation_count),
                .shift = -@as(i16, @intCast(source_offset)),
            };
            self.candidate_row_count = 1;
            return;
        }
        for (0..self.rows) |logical| {
            const desired = self.current_row_map[logical];
            if (self.row_work[logical] == desired) continue;
            var found = logical + 1;
            while (self.row_work[found] != desired) : (found += 1) {}
            const count = found - logical + 1;
            std.debug.assert(self.candidate_row_count < self.candidate_rows.len);
            self.candidate_rows[self.candidate_row_count] = .{
                .first = @intCast(logical),
                .count = @intCast(count),
                .shift = -1,
            };
            self.candidate_row_count += 1;
            std.mem.rotate(u16, self.row_work[logical .. found + 1], 1);
        }
        std.debug.assert(std.mem.eql(
            u16,
            self.row_work[0..self.rows],
            self.current_row_map[0..self.rows],
        ));
    }

    fn clearMutationTracking(self: *Grid) void {
        clearTouchedCellSlots(self.cell_slots, self.touched_cells[0..self.touched_cell_count]);
        clearTouchedRows(self.row_tracked_words, self.touched_rows[0..self.touched_row_count]);
        self.touched_cell_count = 0;
        self.touched_row_count = 0;
        self.dirty_count = 0;
        self.row_dirty_count = 0;
        self.fill_hint_count = 0;
    }

    fn resetCandidate(self: *Grid) void {
        self.candidate_row_count = 0;
        self.candidate_fill_count = 0;
        self.candidate_cell_count = 0;
        self.candidate_glyph_count = 0;
    }
};

fn clearTouchedCellSlots(slots: []u32, touched: []const TouchedCell) void {
    for (touched) |entry| slots[entry.physical_index] = untracked_cell;
}

fn clearTouchedRows(words: []u64, touched: []const u16) void {
    for (touched) |row| setBit(words, row, false);
}

fn normalizeCodepoint(codepoint: u21) u8 {
    if (codepoint == 0) return 0;
    if (codepoint >= 0x20 and codepoint <= 0x7e) return @intCast(codepoint);
    return '?';
}

fn validateLimits(limits: Limits, rows: u16, cols: u16) Error!usize {
    if (limits.rows == 0 or limits.cols == 0 or
        limits.structured_operations == 0 or limits.sparse_cell_updates == 0 or
        limits.sparse_cell_updates > maximum_cells)
        return error.InvalidLimits;
    const initial_cells = try validateDimensions(limits, rows, cols);
    std.debug.assert(initial_cells > 0);
    const retained_cells = cellCount(limits.rows, limits.cols) catch return error.InvalidLimits;
    if (retained_cells > maximum_cells) return error.InvalidLimits;
    return retained_cells;
}

fn validateDimensions(limits: Limits, rows: u16, cols: u16) Error!usize {
    if (rows == 0 or cols == 0 or rows > limits.rows or cols > limits.cols)
        return error.InvalidGeometry;
    return cellCount(rows, cols) catch return error.InvalidGeometry;
}

fn validateCursor(cursor: Cursor, rows: u16, cols: u16) Error!void {
    if (cursor.visible and (cursor.shape == .hidden or
        cursor.row >= rows or cursor.col >= cols))
        return error.InvalidGeometry;
    if (!cursor.visible and cursor.shape != .hidden)
        return error.InvalidGeometry;
}

fn validateCell(cell: Cell) Error!void {
    if (cell.style.reserved != 0 or
        (cell.codepoint != 0 and (cell.codepoint < 0x20 or cell.codepoint > 0x7e)))
        return error.InvalidIdentity;
}

fn cellCount(rows: u16, cols: u16) error{InvalidGeometry}!usize {
    return std.math.mul(usize, rows, cols) catch return error.InvalidGeometry;
}

fn bit(words: []const u64, index: usize) bool {
    return words[index / 64] & (@as(u64, 1) << @intCast(index % 64)) != 0;
}

fn setBit(words: []u64, index: usize, value: bool) void {
    const mask = @as(u64, 1) << @intCast(index % 64);
    if (value)
        words[index / 64] |= mask
    else
        words[index / 64] &= ~mask;
}

fn rotateRows(target: []u16, source: []const u16, shift: i16) void {
    const count: i32 = @intCast(target.len);
    const normalized: i32 = @mod(@as(i32, shift), count);
    for (target, 0..) |*entry, index| {
        const source_index: usize = @intCast(@mod(@as(i32, @intCast(index)) - normalized, count));
        entry.* = source[source_index];
    }
}

fn testCell(codepoint: u21) Cell {
    return Cell.init(
        codepoint,
        .{ .r = 0xee, .g = 0xee, .b = 0xee },
        .{ .r = 0x11, .g = 0x11, .b = 0x11 },
        .{ .r = 0x88, .g = 0x88, .b = 0x88 },
        .{},
    );
}

fn acceptInitial(grid: *Grid) !void {
    const update = (try grid.prepare()).?;
    try std.testing.expect(update.replacement != null);
    try grid.complete();
}

fn applyPendingTerminalTransaction(
    terminal: *howl_vt.Terminal,
    grid: *Grid,
) !void {
    const transaction = terminal.renderTransaction() orelse return;
    try applyTransaction(grid, transaction);
    terminal.consumeRenderTransaction();
}

fn feedTerminalBytes(
    terminal: *howl_vt.Terminal,
    grid: *Grid,
    bytes: []const u8,
) !void {
    for (bytes) |byte| {
        const summary = try terminal.feedRenderByte(byte, 0);
        std.mem.doNotOptimizeAway(summary);
        try applyPendingTerminalTransaction(terminal, grid);
    }
}

fn expectedTerminalCell(
    terminal: *const howl_vt.Terminal,
    cell: howl_vt.Terminal.Cell,
) Cell {
    const presentation = terminal.presentation();
    var foreground = cell.attrs.fg.resolve(presentation.foreground, &presentation.palette);
    var background = cell.attrs.bg.resolve(presentation.background, &presentation.palette);
    if (cell.attrs.reverse != presentation.reverse_screen)
        std.mem.swap(howl_vt.Terminal.Rgb, &foreground, &background);
    const underline = cell.attrs.underline_color.resolve(foreground, &presentation.palette);
    const codepoint: u21 = if (cell.x != 0 or cell.y != 0 or cell.attrs.invisible)
        0
    else if (cell.codepoint <= std.math.maxInt(u21))
        @intCast(cell.codepoint)
    else
        0xfffd;
    return Cell.init(
        codepoint,
        .{ .r = foreground.r, .g = foreground.g, .b = foreground.b },
        .{ .r = background.r, .g = background.g, .b = background.b },
        .{ .r = underline.r, .g = underline.g, .b = underline.b },
        .{
            .bold = cell.attrs.bold,
            .dim = cell.attrs.dim,
            .italic = cell.attrs.italic,
            .underline = cell.attrs.underline,
            .strikethrough = cell.attrs.strikethrough,
        },
    );
}

fn expectGridMatchesTerminal(
    grid: *const Grid,
    terminal: *const howl_vt.Terminal,
) !void {
    const view = terminal.semanticView(0);
    try std.testing.expectEqual(view.rows, grid.rows);
    try std.testing.expectEqual(view.cols, grid.cols);
    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < view.cols) : (col += 1) {
            try std.testing.expectEqualDeep(
                expectedTerminalCell(terminal, view.cellInfoAt(row, col)),
                try grid.current(row, col),
            );
        }
    }
}

fn initTerminalGrid(
    rows: u16,
    cols: u16,
) !struct { howl_vt.Terminal, Grid } {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, rows, cols);
    errdefer terminal.deinit();
    var grid = try Grid.init(
        std.testing.allocator,
        .{
            .rows = 16,
            .cols = 32,
            .structured_operations = maximum_cells,
            .sparse_cell_updates = maximum_cells,
        },
        rows,
        cols,
        testCell(' '),
    );
    errdefer grid.deinit();
    try terminal.enableRenderJournal();
    try applyPendingTerminalTransaction(&terminal, &grid);
    try acceptInitial(&grid);
    return .{ terminal, grid };
}

test "parser bytes keep VT and retained Render cells equal across shell operations" {
    var owners = try initTerminalGrid(4, 12);
    defer owners[1].deinit();
    defer owners[0].deinit();

    const streams = [_][]const u8{
        "alpha",
        "\r\nbeta",
        "\x1b[1;1H\x1b[31;1mZ\x1b[0m",
        "\x1b[2;2H\x1b[2@XY",
        "\x1b[3;2H\x1b[2P",
        "\x1b[4;1Hlast\r\nscroll",
        "\x1b[2;1H\x1b[2K",
    };
    for (streams) |stream| {
        try feedTerminalBytes(&owners[0], &owners[1], stream);
        try expectGridMatchesTerminal(&owners[1], &owners[0]);
    }
}

test "alternate screen replacement keeps VT and retained Render cells equal" {
    var owners = try initTerminalGrid(3, 8);
    defer owners[1].deinit();
    defer owners[0].deinit();

    try feedTerminalBytes(&owners[0], &owners[1], "primary");
    try expectGridMatchesTerminal(&owners[1], &owners[0]);
    try feedTerminalBytes(&owners[0], &owners[1], "\x1b[?1049halt");
    try expectGridMatchesTerminal(&owners[1], &owners[0]);
    try feedTerminalBytes(&owners[0], &owners[1], "\x1b[?1049l");
    try expectGridMatchesTerminal(&owners[1], &owners[0]);
}

test "palette and reverse-screen changes keep resolved Render cells equal" {
    var owners = try initTerminalGrid(2, 8);
    defer owners[1].deinit();
    defer owners[0].deinit();

    try feedTerminalBytes(&owners[0], &owners[1], "\x1b[31mred\x1b[0m");
    try feedTerminalBytes(&owners[0], &owners[1], "\x1b]4;1;#123456\x07");
    try expectGridMatchesTerminal(&owners[1], &owners[0]);
    try feedTerminalBytes(&owners[0], &owners[1], "\x1b[?5h");
    try expectGridMatchesTerminal(&owners[1], &owners[0]);
    try feedTerminalBytes(&owners[0], &owners[1], "\x1b[?5l");
    try expectGridMatchesTerminal(&owners[1], &owners[0]);
}

test "prepared resize publishes one exact Render replacement" {
    var owners = try initTerminalGrid(2, 6);
    defer owners[1].deinit();
    defer owners[0].deinit();

    try feedTerminalBytes(&owners[0], &owners[1], "first\r\nsecond");
    var resize = try owners[0].prepareResize(3, 8);
    defer resize.deinit();
    resize.commit();
    try applyPendingTerminalTransaction(&owners[0], &owners[1]);
    try expectGridMatchesTerminal(&owners[1], &owners[0]);
}

test "pending visual ownership blocks before a later parser byte mutates VT" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try terminal.enableRenderJournal();
    const sequence = terminal.semanticSequence();
    const before = terminal.semanticView(0).cellInfoAt(0, 0);

    try std.testing.expectError(
        error.TransactionPending,
        terminal.feedRenderByte('x', 0),
    );
    try std.testing.expectEqual(sequence, terminal.semanticSequence());
    try std.testing.expectEqualDeep(before, terminal.semanticView(0).cellInfoAt(0, 0));

    terminal.consumeRenderTransaction();
    const summary = try terminal.feedRenderByte('x', 0);
    try std.testing.expect(summary.stateChanged());
    try std.testing.expectEqual(@as(u21, 'x'), terminal.semanticView(0).cellInfoAt(0, 0).codepoint);
}

fn gridAllocationFailure(allocator: std.mem.Allocator) !void {
    var grid = try Grid.init(
        allocator,
        .{ .rows = 2, .cols = 2, .structured_operations = 2, .sparse_cell_updates = 4 },
        2,
        2,
        testCell(' '),
    );
    defer grid.deinit();
}

test "resolved terminal cell is exactly eleven bytes" {
    try std.testing.expectEqual(@as(usize, 11), @sizeOf(Cell));
    try std.testing.expectEqual(@as(usize, 1), @alignOf(Cell));
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(Cursor));
    const normalized = Cell.init(
        0x10ffff,
        .{ .r = 1, .g = 2, .b = 3 },
        .{ .r = 4, .g = 5, .b = 6 },
        .{ .r = 7, .g = 8, .b = 9 },
        .{ .reserved = 7 },
    );
    try std.testing.expectEqual(@as(u8, '?'), normalized.codepoint);
    try std.testing.expectEqual(@as(u3, 0), normalized.style.reserved);
}

test "maximum-cell retained CPU memory equation is exact" {
    const limits = Limits{
        .rows = 128,
        .cols = 512,
        .structured_operations = maximum_cells,
        .sparse_cell_updates = maximum_cells,
    };
    try std.testing.expectEqual(@as(usize, 376), @sizeOf(Grid));
    try std.testing.expectEqual(@as(usize, 6_556_544), try retainedCpuBytes(limits));
}

test "every construction allocation failure retains no partial owner" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        gridAllocationFailure,
        .{},
    );
}

test "ordered four then five cancels before backend work" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 2, .cols = 4, .structured_operations = 4, .sparse_cell_updates = 8 },
        2,
        4,
        testCell('5'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    try grid.set(0, 0, testCell('4'));
    try std.testing.expectEqual(@as(u8, '4'), (try grid.current(0, 0)).codepoint);
    try grid.set(0, 0, testCell('5'));
    try std.testing.expectEqual(@as(u8, '5'), (try grid.current(0, 0)).codepoint);
    try std.testing.expect((try grid.prepare()) == null);
}

test "more than 128 ordered scrolls and fills coalesce to final equality" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 4, .cols = 4, .structured_operations = 8, .sparse_cell_updates = 16 },
        4,
        4,
        testCell('5'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);

    for (0..80) |_| {
        try grid.copyRows(1, 0, 3);
        try grid.fill(3, 0, 1, 4, testCell('4'));
        try grid.fill(3, 0, 1, 4, testCell('5'));
    }
    for (0..4) |row| for (0..4) |col|
        try std.testing.expectEqual(
            @as(u8, '5'),
            (try grid.current(@intCast(row), @intCast(col))).codepoint,
        );
    try std.testing.expect((try grid.prepare()) == null);
}

test "one-cell completion clears only its touched identity at maximum grid size" {
    var slots: [maximum_cells]u32 = @splat(0x1234_5678);
    const touched = [_]TouchedCell{.{
        .physical_index = maximum_cells - 1,
        .baseline = testCell('5'),
    }};
    clearTouchedCellSlots(&slots, &touched);
    try std.testing.expectEqual(@as(u32, 0x1234_5678), slots[0]);
    try std.testing.expectEqual(@as(u32, 0x1234_5678), slots[maximum_cells - 2]);
    try std.testing.expectEqual(untracked_cell, slots[maximum_cells - 1]);

    var row_words: [8]u64 = @splat(std.math.maxInt(u64));
    clearTouchedRows(&row_words, &.{63});
    try std.testing.expectEqual(std.math.maxInt(u64), row_words[1]);
    try std.testing.expect(!bit(&row_words, 63));
}

test "one cell and one style change lower as one sparse update" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 64, .cols = 64, .structured_operations = 4, .sparse_cell_updates = 1 },
        64,
        64,
        testCell('x'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    var changed = testCell('y');
    changed.style.bold = true;
    try grid.set(63, 63, changed);
    const update = (try grid.prepare()).?;
    try std.testing.expectEqual(@as(usize, 1), update.cells.len);
    try std.testing.expectEqual(@as(usize, 0), update.fills.len);
    try std.testing.expectEqual(@as(usize, 0), update.row_rotations.len);
    try grid.complete();
}

test "partially unchanged fill uploads only its final changed cell" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 1, .cols = 4, .structured_operations = 2, .sparse_cell_updates = 4 },
        1,
        4,
        testCell('a'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    try grid.set(0, 0, testCell('b'));
    const first = (try grid.prepare()).?;
    try std.testing.expectEqual(@as(usize, 1), first.cells.len);
    try grid.complete();

    try grid.fill(0, 0, 1, 4, testCell('a'));
    const update = (try grid.prepare()).?;
    try std.testing.expectEqual(@as(usize, 0), update.fills.len);
    try std.testing.expectEqual(@as(usize, 1), update.cells.len);
    try std.testing.expectEqual(@as(u32, 0), update.cells[0].physical_index);
    try grid.complete();
}

test "one-row scroll lowers row identity and exposed row only" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 4, .cols = 5, .structured_operations = 8, .sparse_cell_updates = 5 },
        4,
        5,
        testCell('a'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    try grid.copyRows(1, 0, 3);
    try grid.fill(3, 0, 1, 5, testCell(' '));
    const update = (try grid.prepare()).?;
    try std.testing.expectEqual(@as(usize, 1), update.row_rotations.len);
    try std.testing.expectEqual(@as(i16, -1), update.row_rotations[0].shift);
    try std.testing.expectEqual(@as(usize, 1), update.fills.len);
    try std.testing.expectEqual(@as(u32, 5), update.fills[0].count);
    try std.testing.expectEqual(@as(usize, 0), update.cells.len);
    try grid.complete();
}

test "rectangular copy masked erase and recolor apply exact identities" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 3, .cols = 4, .structured_operations = 8, .sparse_cell_updates = 12 },
        3,
        4,
        testCell('a'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    try grid.set(0, 0, testCell('x'));
    try grid.set(0, 1, testCell('y'));
    try grid.copyRect(0, 0, 1, 2, 1, 1);
    try std.testing.expectEqual(@as(u8, 'x'), (try grid.current(1, 1)).codepoint);
    try std.testing.expectEqual(@as(u8, 'y'), (try grid.current(1, 2)).codepoint);
    try grid.maskedFill(0, 0, 1, 4, &.{0b0000_0101}, testCell(' '));
    try std.testing.expectEqual(@as(u8, ' '), (try grid.current(0, 0)).codepoint);
    try std.testing.expectEqual(@as(u8, 'y'), (try grid.current(0, 1)).codepoint);
    try std.testing.expectEqual(@as(u8, ' '), (try grid.current(0, 2)).codepoint);
    var foreground: [12]u8 = @splat(0);
    var background: [12]u8 = @splat(0);
    var underline: [12]u8 = @splat(0);
    foreground[6] = 1;
    background[6] = 2;
    underline[6] = 3;
    var rgb: [256]Rgb = @splat(.{ .r = 0, .g = 0, .b = 0 });
    rgb[1] = .{ .r = 1, .g = 2, .b = 3 };
    rgb[2] = .{ .r = 4, .g = 5, .b = 6 };
    rgb[3] = .{ .r = 7, .g = 8, .b = 9 };
    try grid.recolor(&foreground, &background, &underline, &rgb);
    const recolored = try grid.current(1, 2);
    try std.testing.expectEqualDeep(rgb[1], recolored.foreground);
    try std.testing.expectEqualDeep(rgb[2], recolored.background);
    try std.testing.expectEqualDeep(rgb[3], recolored.underline_color);
}

test "visual patch is ordered and cancels across the maximum grid" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 128, .cols = 512, .structured_operations = 4, .sparse_cell_updates = maximum_cells },
        128,
        512,
        testCell('x'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    const toggle = Style{ .bold = true, .underline = true };
    try grid.visualPatch(0, 0, 128, 512, null, .{}, .{}, toggle, true, null, null, null);
    const changed = try grid.current(127, 511);
    try std.testing.expect(changed.style.bold);
    try std.testing.expect(changed.style.underline);
    try std.testing.expectEqualDeep(testCell('x').background, changed.foreground);
    try grid.visualPatch(0, 0, 128, 512, null, .{}, .{}, toggle, true, null, null, null);
    try std.testing.expect((try grid.prepare()) == null);
}

test "visual patch mask and final colors affect only selected cells" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 1, .cols = 4, .structured_operations = 2, .sparse_cell_updates = 2 },
        1,
        4,
        testCell('x'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    const fg = Rgb{ .r = 9, .g = 8, .b = 7 };
    try grid.visualPatch(0, 0, 1, 4, &.{0b0000_0101}, .{ .italic = true }, .{}, .{}, false, fg, null, null);
    try std.testing.expect((try grid.current(0, 0)).style.italic);
    try std.testing.expect(!(try grid.current(0, 1)).style.italic);
    try std.testing.expect((try grid.current(0, 2)).style.italic);
    try std.testing.expectEqualDeep(fg, (try grid.current(0, 2)).foreground);
}

test "cursor lowering is independent from cell replacement" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 3, .cols = 3, .structured_operations = 2, .sparse_cell_updates = 1 },
        3,
        3,
        testCell(' '),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    const cursor = Cursor{ .row = 1, .col = 2, .shape = .bar, .visible = true };
    try grid.setCursor(cursor);
    const update = (try grid.prepare()).?;
    try std.testing.expect(update.replacement == null);
    try std.testing.expectEqual(@as(usize, 0), update.cells.len);
    try std.testing.expectEqualDeep(cursor, update.cursor.?);
    try grid.complete();
}

test "candidate capacity and invalid geometry preserve retained states" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 2, .cols = 2, .structured_operations = 1, .sparse_cell_updates = 1 },
        2,
        2,
        testCell('a'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    try std.testing.expectError(error.InvalidGeometry, grid.set(2, 0, testCell('b')));
    var invalid = testCell('b');
    invalid.codepoint = 1;
    try std.testing.expectError(error.InvalidIdentity, grid.set(0, 0, invalid));
    try std.testing.expectEqual(@as(u8, 'a'), (try grid.current(0, 0)).codepoint);
    try grid.set(0, 0, testCell('b'));
    try std.testing.expectError(error.SparseUpdateLimit, grid.set(0, 1, testCell('c')));
    try std.testing.expectEqual(@as(u8, 'b'), (try grid.current(0, 0)).codepoint);
    try std.testing.expectEqual(@as(u8, 'a'), (try grid.current(0, 1)).codepoint);
    const retry = (try grid.prepare()).?;
    try std.testing.expectEqual(@as(usize, 1), retry.cells.len);
    try grid.complete();
}

test "full replacement is explicit and rollback remains retryable" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 3, .cols = 3, .structured_operations = 2, .sparse_cell_updates = 2 },
        2,
        2,
        testCell('a'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    var cells: [6]Cell = undefined;
    @memset(&cells, testCell('z'));
    try grid.replace(.resize, 2, 3, &cells);
    const first = (try grid.prepare()).?;
    try std.testing.expect(first.replacement != null);
    try grid.discard();
    const retry = (try grid.prepare()).?;
    try std.testing.expectEqual(@as(usize, 6), retry.replacement.?.cells.len);
    try std.testing.expectEqual(ReplacementKind.resize, retry.replacement.?.kind);
    try grid.complete();
}

test "replacement geometry waits for a valid static cursor" {
    var grid = try Grid.init(
        std.testing.allocator,
        .{ .rows = 2, .cols = 2, .structured_operations = 1, .sparse_cell_updates = 1 },
        2,
        2,
        testCell('a'),
    );
    defer grid.deinit();
    try acceptInitial(&grid);
    try grid.setCursor(.{ .row = 1, .col = 1, .shape = .block, .visible = true });
    const cell = [_]Cell{testCell('z')};
    try grid.replace(.resize, 1, 1, &cell);
    try std.testing.expectError(error.InvalidGeometry, grid.prepare());
    try std.testing.expectEqual(@as(u8, 'z'), (try grid.current(0, 0)).codepoint);
    try grid.setCursor(.{});
    const retry = (try grid.prepare()).?;
    try std.testing.expectEqual(ReplacementKind.resize, retry.replacement.?.kind);
    try grid.complete();
}
