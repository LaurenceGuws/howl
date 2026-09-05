//! Owns screen-bank cells, cursor, margins, history, reflow, and SGR state.

const std = @import("std");
const scalar_storage = @import("scalar_storage.zig");
const sized_text = @import("sized_text.zig");
const tab_stops_mod = @import("tab_stops.zig");
const unicode = @import("unicode_17.zig");

// File map:
//   - scalar sidecar helpers and shared bounds
//   - the public Screen owner, storage, lifecycle, and mutation districts
//   - logical text projection and the cell-value model
//   - Unicode ownership proofs
//   - resize/reflow machinery and history/output integration proofs

// =============================================================================
// Scalar sidecar helpers and shared bounds
// =============================================================================

fn acceptedTail(
    storage: *const scalar_storage.Storage,
    cell: usize,
    combining_len: u8,
) []const u32 {
    return storage.tail(cell, combining_len) catch
        @panic("accepted scalar range/count mismatch");
}

fn clearAcceptedTail(
    storage: *scalar_storage.Storage,
    cell: usize,
    combining_len: u8,
) void {
    storage.clear(cell, combining_len) catch
        @panic("accepted scalar range/count mismatch");
}

const logical_output_line_bytes_max: usize = 1024 * 1024;

// =============================================================================
// Public Screen owner
// =============================================================================

/// Terminal screen state for cursor, cells, margins, and history.
pub const Screen = struct {
    // -------------------------------------------------------------------------
    // Public vocabulary
    // -------------------------------------------------------------------------

    /// Maximum aggregate bytes retained across finalized logical-output lines.
    pub const retained_output_bytes_max: usize = logical_output_line_bytes_max;

    comptime {
        std.debug.assert(retained_output_bytes_max <= std.math.maxInt(u32));
    }

    /// Failure while validating dimensions or allocating owned Screen storage.
    const InitError = error{ InvalidDimensions, OutOfMemory };

    // Canonical cell, color, and cursor values.

    /// Uses the canonical terminal RGB value for screen state.
    pub const Rgb = ScreenRgb;
    /// Uses the canonical default, indexed, or RGB terminal color.
    pub const Color = ScreenColor;
    /// Uses the semantic terminal-color class without exposing storage layout.
    pub const ColorKind = ScreenColorKind;
    /// Uses the canonical terminal underline style.
    pub const UnderlineStyle = ScreenUnderlineStyle;
    /// Uses the canonical terminal baseline displacement.
    pub const Baseline = ScreenBaseline;
    /// Uses the canonical complete cell attribute value.
    pub const CellAttrs = ScreenCellAttrs;
    /// Distinguishes unprotected, ISO guarded-area, and DEC selective-erase cells.
    /// Uses the canonical terminal cell value.
    pub const Cell = ScreenCell;
    /// Uses the canonical cursor shape.
    pub const CursorShape = ScreenCursorShape;
    /// Uses the canonical cursor style.
    pub const CursorStyle = ScreenCursorStyle;
    const SemanticCursor = ScreenSemanticCursor;
    /// Provides the canonical default cursor style.
    pub const default_cursor_style = initial_cursor_style;
    /// Provides the canonical default foreground color.
    const default_bg = default_cell_background;
    /// Provides the canonical default underline color.
    pub const default_underline_color = default_cell_underline_color;
    /// Provides the canonical default cell attributes.
    pub const default_cell_attrs = initial_cell_attrs;
    /// Provides the canonical blank terminal cell.
    pub const default_cell = blank_cell;
    /// Describes one row's DEC presentation geometry without prescribing caller presentation.
    pub const LineGeometry = enum(u2) {
        single_width,
        double_width,
        double_height_top,
        double_height_bottom,
    };
    /// Resolved inclusive physical bounds for one rectangular operation.
    pub const RectBounds = struct {
        top: u16,
        left: u16,
        bottom: u16,
        right: u16,
    };

    // Screen-local row projection and routed mutation values.

    const RetainedRow = struct {
        cells: []const Cell,
        scalars: *const scalar_storage.Storage,
        scalar_start: usize,
        wrapped: bool,
        geometry: LineGeometry,
    };
    const RetainedLineRange = struct {
        start: u32,
        end: u32,
    };
    /// Finite terminal-semantic mutations owned directly by one screen bank.
    pub const Action = union(enum) {
        cursor_up: u16,
        cursor_down: u16,
        cursor_forward: u16,
        cursor_back: u16,
        cursor_next_line: u16,
        cursor_prev_line: u16,
        cursor_horizontal_absolute: u16,
        cursor_vertical_absolute: u16,
        cursor_position: struct { row: u16, col: u16 },
        write_text: []const u8,
        write_codepoint: u21,
        line_feed,
        next_line,
        carriage_return,
        backspace,
        horizontal_tab,
        horizontal_tab_forward: u16,
        horizontal_tab_back: u16,
        horizontal_tab_set,
        tab_clear_current,
        tab_clear_all,
        reset_default_tab_stops,
        cursor_visible: bool,
        cursor_style: CursorStyleCommand,
        cursor_shape: Screen.CursorShape,
        cursor_color: ?Screen.Rgb,
        cursor_text_color: ?Screen.Rgb,
        auto_wrap: bool,
        origin_mode: bool,
        insert_mode: bool,
        left_right_margin_mode: bool,
        hard_reset,
    };
    /// Borrows SGR values and records semantic colon adjacency independently
    /// of parser storage.
    pub const SgrOperands = struct {
        /// Maximum values and separator positions accepted by Screen SGR.
        pub const capacity: usize = @bitSizeOf(u32);

        values: []const i32,
        colon_after: u32 = 0,

        fn colonAfter(self: SgrOperands, index: u8) bool {
            if (index >= capacity) return false;
            return self.colon_after & (@as(u32, 1) << @intCast(index)) != 0;
        }
    };
    const EraseMode = ScreenEraseMode;
    const CellPixelSize = struct {
        width: u32,
        height: u32,
    };
    const row_wrapped_bit: u8 = 1;
    const row_geometry_shift: u3 = 1;
    const row_geometry_mask: u8 = 0b110;

    // -------------------------------------------------------------------------
    // Retained screen-bank owners
    // -------------------------------------------------------------------------

    // Geometry, cursor, modes, margins, and row orientation.
    allocator: ?std.mem.Allocator,
    rows: u16,
    cols: u16,
    cursor: SemanticCursor,
    wrap_pending: bool,
    auto_wrap: bool,
    origin_mode: bool,
    insert_mode: bool,
    left_right_margin_mode: bool,
    left_margin: u16,
    right_margin: u16,
    attr_change_extent_rect: bool,
    view_padding_rows: u16,
    row_origin: u16,
    scroll_top: u16,
    scroll_bottom: u16,

    // Visible cell plane and scalar sidecar.
    cells: ?[]Cell,
    scalars: ?scalar_storage.Storage,
    row_flags: ?[]u8,

    // Projected scrollback ring and its transactional scalar plans.
    history: ?[]Cell,
    history_scalars: ?scalar_storage.Storage,
    history_plan: ?[]scalar_storage.Range,
    history_plan_outgoing: ?[]u8,
    history_plan_incoming: ?[]u8,
    history_flags: ?[]u8,
    history_capacity: u16,
    history_count: u32,
    history_write_idx: u32,
    history_row_base: u32,

    // Bounded prefix of the one logical line cut by the oldest retained row.
    history_boundary_text: ?[]u8,
    history_boundary_stored: usize,
    history_boundary_total: usize,
    history_boundary_active: bool,

    // Finalized logical-output descriptors and circular text storage.
    output_lines: ?[]OutputLine,
    output_lines_start: u32,
    output_lines_count: u16,
    output_text: ?[]u8,
    output_text_start: u32,
    output_bytes: usize,
    next_output_id: u64,

    // Loss identity, repeat source, rendition, tab, and pixel-size state.
    history_loss_generation: u64,
    last_graphic: ?LastGraphic,
    current_attrs: CellAttrs,
    tab_stops: tab_stops_mod.State,
    cell_pixel_size: ?CellPixelSize,

    // -------------------------------------------------------------------------
    // Construction and owned storage
    // -------------------------------------------------------------------------

    fn cellCount(rows: u16, cols: u16) u32 {
        return @as(u32, rows) * @as(u32, cols);
    }

    fn initBase(
        allocator: ?std.mem.Allocator,
        rows: u16,
        cols: u16,
        cursor_style_default: CursorStyle,
        cells: ?[]Cell,
        row_flags: ?[]u8,
        history: ?[]Cell,
        history_flags: ?[]u8,
        history_capacity: u16,
        tab_stops: tab_stops_mod.State,
    ) Screen {
        return .{
            .allocator = allocator,
            .rows = rows,
            .cols = cols,
            .cursor = ScreenSemanticCursor.init(cursor_style_default),
            .wrap_pending = false,
            .auto_wrap = true,
            .origin_mode = false,
            .insert_mode = false,
            .left_right_margin_mode = false,
            .left_margin = 0,
            .right_margin = cols -| 1,
            .attr_change_extent_rect = false,
            .view_padding_rows = 0,
            .row_origin = 0,
            .scroll_top = 0,
            .scroll_bottom = rows -| 1,
            .cells = cells,
            .scalars = null,
            .row_flags = row_flags,
            .history = history,
            .history_scalars = null,
            .history_plan = null,
            .history_plan_outgoing = null,
            .history_plan_incoming = null,
            .history_flags = history_flags,
            .history_capacity = history_capacity,
            .history_count = 0,
            .history_write_idx = 0,
            .history_row_base = 0,
            .history_boundary_text = null,
            .history_boundary_stored = 0,
            .history_boundary_total = 0,
            .history_boundary_active = false,
            .output_lines = null,
            .output_lines_start = 0,
            .output_lines_count = 0,
            .output_text = null,
            .output_text_start = 0,
            .output_bytes = 0,
            .next_output_id = 1,
            .history_loss_generation = 0,
            .last_graphic = null,
            .current_attrs = initial_cell_attrs,
            .tab_stops = tab_stops,
            .cell_pixel_size = null,
        };
    }

    /// Initialize cursor-only grid state.
    pub fn init(rows: u16, cols: u16) Screen {
        return initWithDefaultCursorStyle(rows, cols, initial_cursor_style);
    }

    fn initWithDefaultCursorStyle(rows: u16, cols: u16, cursor_style_default: CursorStyle) Screen {
        return initBase(null, rows, cols, cursor_style_default, null, null, null, null, 0, .empty);
    }

    /// Initialize screen with owned cell storage.
    pub fn initWithCells(allocator: std.mem.Allocator, rows: u16, cols: u16) InitError!Screen {
        return initWithCellsAndDefaultCursorStyle(allocator, rows, cols, initial_cursor_style);
    }

    fn initOwnedVisibleGrid(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
        cursor_style_default: CursorStyle,
    ) InitError!Screen {
        if (rows == 0 or cols == 0) return error.InvalidDimensions;
        const cell_count = cellCount(rows, cols);
        const cells: ?[]Cell = if (cell_count > 0) blk: {
            const buf = try allocator.alloc(Cell, @intCast(cell_count));
            @memset(buf, blank_cell);
            break :blk buf;
        } else null;
        errdefer if (cells) |c| allocator.free(c);
        const row_flags: ?[]u8 = if (rows > 0) blk: {
            const buf = try allocator.alloc(u8, rows);
            @memset(buf, 0);
            break :blk buf;
        } else null;
        errdefer if (row_flags) |buf| allocator.free(buf);
        var tab_stops = try tab_stops_mod.State.init(allocator, cols);
        errdefer tab_stops.deinit(allocator);
        var result = initBase(
            allocator,
            rows,
            cols,
            cursor_style_default,
            cells,
            row_flags,
            null,
            null,
            0,
            tab_stops,
        );
        result.scalars = scalar_storage.Storage.init(allocator, cell_count) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCapacity => return error.InvalidDimensions,
        };
        errdefer if (result.scalars) |*storage| storage.deinit();
        return result;
    }

    fn initWithCellsAndDefaultCursorStyle(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
        cursor_style_default: CursorStyle,
    ) InitError!Screen {
        return initOwnedVisibleGrid(allocator, rows, cols, cursor_style_default);
    }

    /// Initialize screen with cells and history storage.
    pub fn initWithCellsAndHistory(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
        history_capacity: u16,
    ) InitError!Screen {
        return initWithCellsHistoryAndDefaultCursorStyle(allocator, rows, cols, history_capacity, initial_cursor_style);
    }

    fn initWithCellsHistoryAndDefaultCursorStyle(
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
        history_capacity: u16,
        cursor_style_default: CursorStyle,
    ) InitError!Screen {
        var screen = try initOwnedVisibleGrid(allocator, rows, cols, cursor_style_default);
        errdefer screen.deinit(allocator);

        screen.history_capacity = if (screen.cells != null) history_capacity else 0;
        try screen.allocateHistoryAuthority(allocator);
        try screen.allocateOutputAuthority(allocator);
        return screen;
    }

    /// Release owned cell and history buffers.
    pub fn deinit(self: *Screen, allocator: std.mem.Allocator) void {
        if (self.cells) |c| allocator.free(c);
        self.cells = null;
        if (self.scalars) |*storage| storage.deinit();
        self.scalars = null;
        if (self.row_flags) |buf| allocator.free(buf);
        self.row_flags = null;
        self.tab_stops.deinit(allocator);
        if (self.history) |h| allocator.free(h);
        self.history = null;
        if (self.history_scalars) |*storage| storage.deinit();
        self.history_scalars = null;
        if (self.history_plan) |plan| allocator.free(plan);
        self.history_plan = null;
        if (self.history_plan_outgoing) |counts| allocator.free(counts);
        self.history_plan_outgoing = null;
        if (self.history_plan_incoming) |counts| allocator.free(counts);
        self.history_plan_incoming = null;
        if (self.history_flags) |buf| allocator.free(buf);
        self.history_flags = null;
        if (self.history_boundary_text) |text| allocator.free(text);
        self.history_boundary_text = null;
        if (self.output_text) |text| allocator.free(text);
        self.output_text = null;
        if (self.output_lines) |lines| allocator.free(lines);
        self.output_lines = null;
    }

    // -------------------------------------------------------------------------
    // Resize authority and replacement installation
    // -------------------------------------------------------------------------

    /// Replace this screen with a reflowed grid of the requested dimensions.
    ///
    /// Allocation failure leaves this screen unchanged. Successful replacement
    /// preserves logical content and configured cursor defaults, resets margins
    /// and physical-row geometry to the full new grid, and releases old storage.
    pub fn resize(self: *Screen, allocator: std.mem.Allocator, rows: u16, cols: u16) ReflowError!void {
        var replacement = try self.prepareResize(allocator, rows, cols);
        std.mem.swap(Screen, self, &replacement);
        replacement.deinit(allocator);
    }

    /// Build complete reflowed screen state without mutating this screen.
    ///
    /// The caller owns the returned Screen and must call `deinit` unless it
    /// transfers ownership by swapping it into a Screen owner.
    pub fn prepareResize(
        self: *const Screen,
        allocator: std.mem.Allocator,
        rows: u16,
        cols: u16,
    ) ReflowError!Screen {
        var lines = try self.collectLogicalSnapshot(allocator);
        defer lines.deinit(allocator);
        for (lines.logical_lines.items) |*line| {
            for (line.cells.items) |*cell| {
                if (!isSemanticWideCell(cell.*) and
                    (cell.width != 1 or cell.height != 1 or
                        cell.x != 0 or cell.y != 0))
                {
                    cell.* = blank_cell;
                }
            }
        }
        omitUnrepresentableSemanticWidths(&lines, cols);

        var reflow = try reflowLogicalLines(allocator, lines, cols);
        defer reflow.deinit(allocator);

        const projection = projectViewport(screenCount32(lines.logical_lines.items.len), reflow, rows);
        var buffers = try allocResizeBuffers(allocator, rows, cols, self.tab_stops);
        errdefer buffers.deinit(allocator);

        try copyVisibleRows(&buffers, reflow, projection, cols);
        var replacement = self.replacementBase(allocator);
        replacement.installResizeState(rows, cols, buffers.take());
        errdefer replacement.deinit(allocator);
        try replacement.allocateHistoryAuthority(allocator);
        try replacement.allocateOutputAuthority(allocator);
        replacement.cloneOutputAuthority(self);
        try replacement.rebuildResizeAuthority(reflow, projection);
        replacement.restoreResizeCursor(rows, cols, reflow, projection);
        return replacement;
    }

    fn allocateHistoryAuthority(
        self: *Screen,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!void {
        if (self.history_capacity == 0) return;
        std.debug.assert(self.history == null);
        std.debug.assert(self.history_flags == null);
        std.debug.assert(self.history_plan == null);
        std.debug.assert(self.history_plan_outgoing == null);
        std.debug.assert(self.history_plan_incoming == null);
        std.debug.assert(self.history_scalars == null);
        std.debug.assert(self.history_count == 0);

        const history_cells = std.math.mul(
            usize,
            self.history_capacity,
            self.cols,
        ) catch return error.OutOfMemory;
        const history = try allocator.alloc(Cell, history_cells);
        errdefer allocator.free(history);
        // Unoccupied projected rows are unreachable through history_count and
        // remain untouched until their first complete-row commit. Reserving the
        // fixed owner at initialization must not fault every future row into
        // resident memory while the terminal is idle.
        const flags = try allocator.alloc(u8, self.history_capacity);
        errdefer allocator.free(flags);
        @memset(flags, 0);
        var scalars = scalar_storage.Storage.init(
            allocator,
            history_cells,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCapacity => return error.OutOfMemory,
        };
        errdefer scalars.deinit();
        const plan = try allocator.alloc(scalar_storage.Range, self.cols);
        errdefer allocator.free(plan);
        @memset(plan, .none);
        const outgoing = try allocator.alloc(u8, self.cols);
        errdefer allocator.free(outgoing);
        @memset(outgoing, 0);
        const incoming = try allocator.alloc(u8, self.cols);
        @memset(incoming, 0);

        self.history = history;
        self.history_flags = flags;
        self.history_scalars = scalars;
        self.history_plan = plan;
        self.history_plan_outgoing = outgoing;
        self.history_plan_incoming = incoming;
        self.history_write_idx = 0;
    }

    fn allocateOutputAuthority(
        self: *Screen,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!void {
        if (self.history_capacity == 0) return;
        std.debug.assert(self.output_lines == null);
        std.debug.assert(self.output_text == null);
        std.debug.assert(self.history_boundary_text == null);
        std.debug.assert(self.output_lines_count == 0);
        std.debug.assert(self.output_bytes == 0);

        const lines = try allocator.alloc(OutputLine, self.history_capacity);
        errdefer allocator.free(lines);
        for (lines) |*line| line.* = OutputLine.empty;
        const text = try allocator.alloc(u8, retained_output_bytes_max);
        errdefer allocator.free(text);
        const boundary_text = try allocator.alloc(u8, retained_output_bytes_max);

        self.output_lines = lines;
        self.output_text = text;
        self.history_boundary_text = boundary_text;
        self.output_lines_start = 0;
        self.output_text_start = 0;
    }

    fn replacementBase(self: *const Screen, allocator: std.mem.Allocator) Screen {
        var replacement = self.*;
        replacement.allocator = allocator;
        replacement.cells = null;
        replacement.scalars = null;
        replacement.row_flags = null;
        replacement.tab_stops = .empty;
        replacement.history = null;
        replacement.history_scalars = null;
        replacement.history_plan = null;
        replacement.history_plan_outgoing = null;
        replacement.history_plan_incoming = null;
        replacement.history_flags = null;
        replacement.history_count = 0;
        replacement.history_write_idx = 0;
        replacement.history_boundary_text = null;
        replacement.history_boundary_stored = 0;
        replacement.history_boundary_total = 0;
        replacement.history_boundary_active = false;
        replacement.output_lines = null;
        replacement.output_lines_start = 0;
        replacement.output_lines_count = 0;
        replacement.output_text = null;
        replacement.output_text_start = 0;
        replacement.output_bytes = 0;
        return replacement;
    }

    fn installResizeState(self: *Screen, rows: u16, cols: u16, buffers: ResizeBuffers) void {
        self.rows = rows;
        self.cols = cols;
        self.cells = buffers.cells;
        self.scalars = buffers.scalars;
        self.row_flags = buffers.row_flags;
        self.tab_stops = buffers.tab_stops;
        self.history = null;
        self.history_scalars = null;
        self.history_plan = null;
        self.history_plan_outgoing = null;
        self.history_plan_incoming = null;
        self.history_flags = null;
        self.history_count = 0;
        self.history_write_idx = 0;
        self.row_origin = 0;
        self.view_padding_rows = 0;
        self.scroll_top = 0;
        self.scroll_bottom = rows -| 1;
        self.left_right_margin_mode = false;
        self.left_margin = 0;
        self.right_margin = cols -| 1;
        self.attr_change_extent_rect = false;

        std.debug.assert(self.rows == rows);
        std.debug.assert(self.cols == cols);
        std.debug.assert((self.cells != null) == (rows > 0 and cols > 0));
        std.debug.assert((self.scalars != null) == (rows > 0 and cols > 0));
        std.debug.assert((self.row_flags != null) == (rows > 0));
        std.debug.assert(self.tab_stops.ownsColumns(cols));
        if (self.cells) |buf| std.debug.assert(buf.len == cellCount(rows, cols));
        if (self.row_flags) |buf| std.debug.assert(buf.len == rows);
        std.debug.assert(self.history == null);
        std.debug.assert(self.history_flags == null);
        std.debug.assert(self.history_count == 0);
        std.debug.assert(self.history_write_idx == 0);
        std.debug.assert(self.row_origin == 0);
        std.debug.assert(self.view_padding_rows == 0);
        std.debug.assert(self.scroll_top == 0);
        std.debug.assert(self.scroll_bottom == rows -| 1);
        std.debug.assert(self.left_right_margin_mode == false);
        std.debug.assert(self.left_margin == 0);
        std.debug.assert(self.right_margin == cols -| 1);
    }

    fn cloneOutputAuthority(self: *Screen, source: *const Screen) void {
        if (self.history_capacity == 0) {
            std.debug.assert(self.output_lines == null);
            std.debug.assert(self.output_text == null);
            std.debug.assert(self.history_boundary_text == null);
            std.debug.assert(source.output_lines == null);
            std.debug.assert(source.output_text == null);
            std.debug.assert(source.history_boundary_text == null);
            return;
        }
        const lines = self.output_lines orelse unreachable;
        const source_lines = source.output_lines orelse unreachable;
        const text = self.output_text orelse unreachable;
        const source_text = source.output_text orelse unreachable;
        const boundary_text = self.history_boundary_text orelse unreachable;
        const source_boundary_text = source.history_boundary_text orelse unreachable;
        std.debug.assert(lines.len == source_lines.len);
        std.debug.assert(text.len == source_text.len);
        std.debug.assert(boundary_text.len == source_boundary_text.len);
        for (lines, source_lines) |*destination, value| destination.* = value;
        if (source.output_bytes != 0) {
            const start: usize = source.output_text_start;
            const first_len = @min(source.output_bytes, source_text.len - start);
            @memcpy(text[start..][0..first_len], source_text[start..][0..first_len]);
            const second_len = source.output_bytes - first_len;
            if (second_len != 0) {
                @memcpy(text[0..second_len], source_text[0..second_len]);
            }
        }
        if (source.history_boundary_stored != 0) {
            @memcpy(
                boundary_text[0..source.history_boundary_stored],
                source_boundary_text[0..source.history_boundary_stored],
            );
        }
        self.history_boundary_stored = source.history_boundary_stored;
        self.history_boundary_total = source.history_boundary_total;
        self.history_boundary_active = source.history_boundary_active;
        self.output_lines_start = source.output_lines_start;
        self.output_lines_count = source.output_lines_count;
        self.output_text_start = source.output_text_start;
        self.output_bytes = source.output_bytes;
    }

    fn rebuildResizeAuthority(
        self: *Screen,
        reflow: ReflowState,
        projection: ResizeProjection,
    ) ReflowError!void {
        std.debug.assert(projection.total_rows == screenCount32(reflow.rewrapped.items.len));
        try self.installResizeProjection(reflow, projection);
    }

    fn installResizeProjection(
        self: *Screen,
        reflow: ReflowState,
        projection: ResizeProjection,
    ) ReflowError!void {
        self.history_count = 0;
        self.history_write_idx = 0;
        if (self.history_capacity == 0 or self.cols == 0) return;

        std.debug.assert(projection.visible_start <= screenCount32(reflow.rewrapped.items.len));
        var row_index: u32 = 0;
        while (row_index < projection.visible_start) : (row_index += 1) {
            const row = reflow.rewrapped.items[@intCast(row_index)];
            const row_end = row.start + self.cols;
            std.debug.assert(row.len <= self.cols);
            std.debug.assert(row_end <= screenCount32(reflow.flat_rows.items.len));
            const projected_slot = self.preflightProjectedRow(
                reflow.flat_rows.items[@intCast(row.start)..@intCast(row.start + row.len)],
                &reflow.scalars.?,
                row.start,
            ) orelse return error.ScalarCapacity;
            self.commitProjectedRow(
                projected_slot,
                reflow.flat_rows.items[@intCast(row.start)..@intCast(row.start + row.len)],
                &reflow.scalars.?,
                row.start,
                row.wrapped,
                row.geometry,
                if (self.history_count == self.history_capacity) 1 else 0,
            );
        }
    }

    fn restoreResizeCursor(self: *Screen, rows: u16, cols: u16, reflow: ReflowState, projection: ResizeProjection) void {
        if (rows == 0 or cols == 0 or projection.total_rows == 0) {
            self.cursor.setPositionStructural(0, 0);
            self.wrap_pending = false;
            std.debug.assert(self.cursor.row == 0);
            std.debug.assert(self.cursor.col == 0);
            std.debug.assert(self.wrap_pending == false);
            return;
        }

        const last_visible_row = projection.visible_start + projection.visible_rows_kept - 1;
        const clamped_cursor_row = std.math.clamp(reflow.global_cursor_row, projection.visible_start, last_visible_row);
        const cursor_row: u16 = @intCast(clamped_cursor_row - projection.visible_start);
        self.cursor.setPositionStructural(
            cursor_row,
            @min(reflow.global_cursor_col, self.lineRightBoundary(cursor_row)),
        );
        self.wrap_pending = reflow.next_wrap_pending and
            self.cursor.row < rows and self.cursor.col == self.lineRightBoundary(self.cursor.row);

        std.debug.assert(projection.visible_rows_kept > 0);
        std.debug.assert(clamped_cursor_row >= projection.visible_start);
        std.debug.assert(clamped_cursor_row <= last_visible_row);
        std.debug.assert(self.cursor.row < rows);
        std.debug.assert(self.cursor.col < cols);
        if (self.wrap_pending) std.debug.assert(self.cursor.col == self.lineRightBoundary(self.cursor.row));
    }

    // -------------------------------------------------------------------------
    // Projected history and logical-output retention
    // -------------------------------------------------------------------------

    /// Retain one visible row only after all authority and projection allocations succeed.
    ///
    /// Allocation failure drops this row while preserving paired retained state for the next scroll.
    fn storeHistoryRow(self: *Screen, row: u16) void {
        if (self.history_capacity == 0) return;
        const row_start = self.rowStart(row);
        const len = self.visibleRowContentLen(row);
        const incoming = self.cells.?[row_start..][0..len];
        const slot = self.preflightProjectedRow(
            incoming,
            &self.scalars.?,
            row_start,
        ) orelse {
            self.recordHistoryLoss();
            return;
        };
        self.commitProjectedRow(
            slot,
            incoming,
            &self.scalars.?,
            row_start,
            self.rowWrapped(row),
            self.lineGeometry(row),
            if (self.history_count == self.history_capacity) 1 else 0,
        );
    }

    fn recordHistoryLoss(self: *Screen) void {
        self.history_loss_generation = std.math.add(
            u64,
            self.history_loss_generation,
            1,
        ) catch @panic("terminal history loss generation exhausted");
    }

    /// Finalizes the primary screen's current logical output line.
    pub fn finalizeOutputLine(self: *Screen) void {
        if (self.history_capacity == 0) return;
        const byte_count = openOutputLineByteCount(self);
        if (byte_count > logical_output_line_bytes_max) {
            self.retainOutputLoss(byte_count);
            return;
        }
        self.retainOpenOutputText(byte_count);
    }

    // Finalized output is copied separately because logical-history rows are
    // retained only after leaving the projection, while output identity belongs
    // to the earlier line-finalization boundary and must survive later reflow.
    fn retainOpenOutputText(self: *Screen, byte_count: usize) void {
        std.debug.assert(byte_count <= logical_output_line_bytes_max);
        self.prepareOutputLine(byte_count);
        const start = self.outputTextTail();
        var writer = OutputTextWriter.init(self.output_text.?, start);
        writeOpenOutputLine(self, &writer);
        std.debug.assert(writer.count == byte_count);
        self.commitOutputLine(.{ .text = .{
            .start = start,
            .len = @intCast(byte_count),
        } });
    }

    fn retainOutputText(self: *Screen, text: []const u8) void {
        std.debug.assert(text.len <= logical_output_line_bytes_max);
        self.prepareOutputLine(text.len);
        const start = self.outputTextTail();
        var writer = OutputTextWriter.init(self.output_text.?, start);
        writer.write(text);
        self.commitOutputLine(.{ .text = .{
            .start = start,
            .len = @intCast(text.len),
        } });
    }

    fn retainOutputLoss(self: *Screen, byte_count: usize) void {
        std.debug.assert(byte_count > logical_output_line_bytes_max);
        self.prepareOutputLine(0);
        self.commitOutputLine(.{ .loss = .{
            .byte_count = byte_count,
            .reason = .line_too_long,
        } });
    }

    fn prepareOutputLine(self: *Screen, byte_count: usize) void {
        std.debug.assert(self.history_capacity > 0);
        std.debug.assert(byte_count <= retained_output_bytes_max);
        while (self.output_lines_count == self.history_capacity or
            byte_count > retained_output_bytes_max - self.output_bytes)
        {
            self.evictOldestOutputLine();
        }
    }

    fn commitOutputLine(self: *Screen, value: OutputLine.Value) void {
        const lines = self.output_lines orelse unreachable;
        std.debug.assert(self.output_lines_count < self.history_capacity);
        const slot_index = (self.output_lines_start + self.output_lines_count) %
            @as(u32, @intCast(lines.len));
        const slot = &lines[@intCast(slot_index)];
        std.debug.assert(slot.id == 0);
        slot.* = .{
            .id = self.takeOutputId(),
            .value = value,
        };
        self.output_lines_count += 1;
        self.output_bytes += value.retainedBytes();
        std.debug.assert(self.output_bytes <= retained_output_bytes_max);
    }

    fn evictOldestOutputLine(self: *Screen) void {
        const lines = self.output_lines orelse unreachable;
        std.debug.assert(self.output_lines_count > 0);
        const slot = &lines[@intCast(self.output_lines_start)];
        std.debug.assert(slot.id != 0);
        switch (slot.value) {
            .text => |text| {
                std.debug.assert(text.start == self.output_text_start);
                self.output_bytes -= text.len;
                self.output_text_start = @intCast(
                    (@as(usize, text.start) + text.len) % retained_output_bytes_max,
                );
            },
            .loss => {},
        }
        slot.* = OutputLine.empty;
        self.output_lines_count -= 1;
        self.output_lines_start = (self.output_lines_start + 1) %
            @as(u32, @intCast(lines.len));
        if (self.output_lines_count == 0) {
            std.debug.assert(self.output_bytes == 0);
            self.output_lines_start = 0;
            self.output_text_start = 0;
        }
    }

    fn outputTextTail(self: *const Screen) u32 {
        std.debug.assert(self.output_text != null);
        return @intCast(
            (@as(usize, self.output_text_start) + self.output_bytes) %
                retained_output_bytes_max,
        );
    }

    fn takeOutputId(self: *Screen) u64 {
        const id = self.next_output_id;
        self.next_output_id = std.math.add(u64, id, 1) catch
            @panic("terminal logical output identity exhausted");
        return id;
    }

    /// Clone the finite projected-history and visible rows into one resize snapshot.
    ///
    /// Allocation failure releases partial clones and leaves this Screen unchanged.
    /// Rows older than `history_row_base` are not part of the snapshot and cannot
    /// return after widening.
    fn collectLogicalSnapshot(
        self: *const Screen,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!LogicalSnapshot {
        var result = LogicalSnapshot{};
        errdefer result.deinit(allocator);
        var current_line = LogicalLine{};
        defer current_line.deinit(allocator);

        const cursor_row = self.history_count + self.cursor.row;
        const total = self.retainedRowCount();
        var logical_row: u32 = 0;
        while (logical_row < total) : (logical_row += 1) {
            const row = self.retainedRowAt(logical_row);
            if (logical_row == cursor_row) {
                current_line.cursor_offset =
                    @as(u32, @intCast(current_line.cells.items.len)) +
                    self.cursorOffsetInRow();
            }
            const content_len = self.retainedRowContentLen(row);
            try appendLogicalCells(
                allocator,
                &current_line,
                row.cells[0..content_len],
                row.scalars,
                row.scalar_start,
            );

            if (!row.wrapped) {
                if (current_line.cursor_offset) |offset| {
                    result.cursor_found = true;
                    result.cursor_line_index = @intCast(result.logical_lines.items.len);
                    result.cursor_offset = offset;
                }
                try result.logical_lines.append(allocator, current_line);
                current_line = .{};
            }
        }

        if (current_line.cells.items.len > 0 or
            current_line.cursor_offset != null or
            result.logical_lines.items.len == 0)
        {
            if (current_line.cursor_offset) |offset| {
                result.cursor_found = true;
                result.cursor_line_index = @intCast(result.logical_lines.items.len);
                result.cursor_offset = offset;
            }
            try result.logical_lines.append(allocator, current_line);
            current_line = .{};
        }

        while (result.logical_lines.items.len > 1) {
            const last_idx = result.logical_lines.items.len - 1;
            const last = &result.logical_lines.items[last_idx];
            if (last.cells.items.len > 0) break;
            if (result.cursor_found and result.cursor_line_index == last_idx) break;
            last.deinit(allocator);
            result.logical_lines.items.len = last_idx;
        }
        return result;
    }

    fn cursorOffsetInRow(self: *const Screen) u32 {
        if (self.cols == 0) return 0;
        const line_cols = self.lineColumnCount(self.cursor.row);
        if (self.wrap_pending and self.cursor.col == line_cols - 1) return line_cols;
        return self.cursor.col;
    }

    fn visibleRowContentLen(self: *const Screen, row: u16) u16 {
        const line_cols = self.lineColumnCount(row);
        var col = line_cols;
        while (col > 0) {
            const idx = col - 1;
            const cell = self.cellInfoAt(row, idx);
            if (cell.codepoint != 0) {
                if (isSemanticWideLead(cell)) return @min(
                    line_cols,
                    col + @as(u16, cell.width) - 1,
                );
                return col;
            }
            col -= 1;
        }
        if (self.rowWrapped(row) and line_cols > 0) return line_cols;
        return 0;
    }

    fn preflightProjectedRow(
        self: *Screen,
        incoming: []const Cell,
        incoming_scalars: *const scalar_storage.Storage,
        incoming_start: usize,
    ) ?u32 {
        const flags = self.history_flags orelse return null;
        const history = self.history orelse return null;
        const scalars = if (self.history_scalars) |*storage|
            storage
        else
            return null;
        const plans = self.history_plan orelse return null;
        const outgoing_counts = self.history_plan_outgoing orelse return null;
        const incoming_counts = self.history_plan_incoming orelse return null;
        if (incoming.len > self.cols or plans.len != self.cols or
            outgoing_counts.len != self.cols or
            incoming_counts.len != self.cols)
            return null;
        const capacity = self.projectedCapacity();
        std.debug.assert(self.history_count <= capacity);
        const replacing_occupied = self.history_count == capacity;
        const slot = self.projectedAppendSlot();
        const base = slot * @as(u32, self.cols);
        if (base + self.cols > history.len or slot >= flags.len) return null;
        @memset(plans, .none);
        var col: usize = 0;
        while (col < self.cols) : (col += 1) {
            outgoing_counts[col] = if (replacing_occupied)
                history[base + col].combining_len
            else
                0;
            incoming_counts[col] = if (col < incoming.len)
                incoming[col].combining_len
            else
                0;
            if (!scalars.validRange(base + col, outgoing_counts[col]))
                @panic("accepted projected-history scalar mismatch");
            if (col >= incoming.len) continue;
            if (!incoming_scalars.validRange(
                incoming_start + col,
                incoming_counts[col],
            )) @panic("accepted history-line scalar mismatch");
        }
        col = 0;
        while (col < self.cols) : (col += 1) {
            const count = @as(usize, incoming_counts[col]) -|
                (scalar_storage.inline_scalars - 1);
            if (count == 0) continue;
            plans[col] = scalars.planFirstFit(
                count,
                base,
                outgoing_counts,
                plans[0..col],
                incoming_counts[0..col],
            ) catch return null;
        }
        return slot;
    }

    fn commitProjectedRow(
        self: *Screen,
        slot: u32,
        incoming: []const Cell,
        incoming_scalars: *const scalar_storage.Storage,
        incoming_start: usize,
        wrapped: bool,
        geometry: LineGeometry,
        rows_to_drop: u32,
    ) void {
        const flags = self.history_flags orelse
            @panic("projected-history flags disappeared after preflight");
        const history = self.history orelse
            @panic("projected-history cells disappeared after preflight");
        const scalars = if (self.history_scalars) |*storage|
            storage
        else
            @panic("projected-history scalars disappeared after preflight");
        const plans = self.history_plan orelse
            @panic("projected-history plan disappeared after preflight");
        const outgoing_counts = self.history_plan_outgoing orelse
            @panic("projected-history counts disappeared after preflight");
        const incoming_counts = self.history_plan_incoming orelse
            @panic("projected-history counts disappeared after preflight");
        const drop = @min(rows_to_drop, self.history_count);
        if (drop != 0) self.recordDroppedProjectedRows(drop);
        const base = slot * @as(u32, self.cols);
        var col: usize = 0;
        while (col < self.cols) : (col += 1)
            clearAcceptedTail(scalars, base + col, outgoing_counts[col]);
        col = 0;
        while (col < incoming.len) : (col += 1) {
            const count = @as(usize, incoming_counts[col]) -|
                (scalar_storage.inline_scalars - 1);
            if (count == 0) continue;
            const values = acceptedTail(
                incoming_scalars,
                incoming_start + col,
                incoming_counts[col],
            );
            var prepared = scalars.prepare(values) catch
                @panic("projected-history preflight diverged");
            prepared.commitPlanned(plans[col], base + col, 0) catch
                @panic("projected-history first-fit plan diverged");
        }
        @memset(history[base..][0..self.cols], blank_cell);
        @memcpy(history[base..][0..incoming.len], incoming);
        flags[slot] = rowFlags(wrapped, geometry);
        if (drop != 0) {
            var logical_row: u32 = 0;
            while (logical_row < drop) : (logical_row += 1) {
                const outgoing_slot = self.historySlotForLogicalRow(logical_row) orelse
                    @panic("accepted projected-history row missing");
                if (outgoing_slot != slot) self.clearProjectedSlot(outgoing_slot);
            }
            self.advanceOldestProjectedRows(drop);
            if (self.history_count == 0) self.history_write_idx = slot;
        }
        self.history_count += 1;
    }

    fn dropOldestProjectedRows(self: *Screen, row_count: u32) void {
        if (row_count == 0 or self.history_count == 0) return;

        const drop = @min(row_count, self.history_count);
        self.recordDroppedProjectedRows(drop);
        var logical_row: u32 = 0;
        while (logical_row < drop) : (logical_row += 1) {
            const slot = self.historySlotForLogicalRow(logical_row) orelse
                @panic("accepted projected-history row missing");
            self.clearProjectedSlot(slot);
        }
        self.advanceOldestProjectedRows(drop);
    }

    fn advanceOldestProjectedRows(self: *Screen, row_count: u32) void {
        if (row_count == 0 or self.history_count == 0) return;
        const drop = @min(row_count, self.history_count);
        const capacity = self.projectedCapacity();
        std.debug.assert(drop <= self.history_count);
        if (drop == self.history_count or capacity == 0) {
            self.history_row_base += self.history_count;
            self.history_count = 0;
            self.history_write_idx = 0;
            return;
        }

        std.debug.assert(self.history_write_idx < capacity);
        self.history_write_idx = (self.history_write_idx + drop) % capacity;
        self.history_count -= drop;
        self.history_row_base += drop;
    }

    fn clearProjectedSlot(self: *Screen, slot: u32) void {
        const history = self.history orelse
            @panic("accepted projected-history cells missing");
        const scalars = if (self.history_scalars) |*storage|
            storage
        else
            @panic("accepted projected-history scalars missing");
        const base = slot * @as(u32, self.cols);
        if (base + self.cols > history.len)
            @panic("accepted projected-history slot invalid");
        var col: u32 = 0;
        while (col < self.cols) : (col += 1)
            clearAcceptedTail(
                scalars,
                base + col,
                history[base + col].combining_len,
            );
        @memset(history[base..][0..self.cols], blank_cell);
        if (self.history_flags) |flags| flags[slot] = 0;
    }

    // -------------------------------------------------------------------------
    // Reset and borrowed observation
    // -------------------------------------------------------------------------

    /// Reset visible grid state to defaults.
    pub fn reset(self: *Screen) void {
        self.cursor.reset();
        self.wrap_pending = false;
        self.auto_wrap = true;
        self.origin_mode = false;
        self.insert_mode = false;
        self.left_right_margin_mode = false;
        self.left_margin = 0;
        self.right_margin = self.cols -| 1;
        self.attr_change_extent_rect = false;
        self.view_padding_rows = 0;
        self.row_origin = 0;
        self.scroll_top = 0;
        self.scroll_bottom = self.rows -| 1;
        self.last_graphic = null;
        self.current_attrs = initial_cell_attrs;
        if (self.cells) |c| @memset(c, blank_cell);
        if (self.scalars) |*storage| storage.clearAll();
        if (self.row_flags) |buf| @memset(buf, 0);
        self.tab_stops.reset();
    }

    // Applies DECSTR's bank-local defaults without erasing cells or moving the cursor.
    /// Resets soft terminal state while preserving cells and retained history.
    pub fn softReset(self: *Screen) bool {
        const cursor_before = self.cursor;
        var changed = self.wrap_pending or !self.auto_wrap or self.origin_mode or
            self.attr_change_extent_rect or self.scroll_top != 0 or self.scroll_bottom != self.rows -| 1 or
            !std.meta.eql(self.current_attrs, initial_cell_attrs);

        self.wrap_pending = false;
        self.auto_wrap = true;
        self.origin_mode = false;
        self.attr_change_extent_rect = false;
        self.scroll_top = 0;
        self.scroll_bottom = self.rows -| 1;
        self.current_attrs = initial_cell_attrs;
        self.cursor.restoreDefaultStyle();
        changed = !std.meta.eql(cursor_before, self.cursor) or changed;

        changed = self.tab_stops.resetChanged() or changed;
        var row: u16 = 0;
        while (row < self.rows) : (row += 1) {
            if (self.lineGeometry(row) != .single_width) changed = true;
            self.resetLineGeometry(row);
        }
        return changed;
    }

    /// Replaces the configured cursor default on this screen.
    pub fn setDefaultCursorStyle(self: *Screen, style: CursorStyle) void {
        self.cursor.setDefaultStyle(style);
    }

    /// Read visible cell value by row and column.
    pub fn cellAt(self: *const Screen, row: u16, col: u16) u21 {
        return @intCast(self.cellInfoAt(row, col).codepoint);
    }

    /// Returns a copied visible cell, or the blank default outside the grid.
    pub fn cellInfoAt(self: *const Screen, row: u16, col: u16) Cell {
        const c = self.cells orelse return blank_cell;
        if (row >= self.rows or col >= self.cols) return blank_cell;
        const start = self.rowStart(row);
        return c[@intCast(start + @as(u32, col))];
    }

    /// Copies one complete visible lead-cell scalar sequence.
    ///
    /// Continuation coordinates resolve to their exact lead cell. The returned
    /// slice borrows caller storage and remains valid independently of Screen
    /// mutation.
    pub fn cellScalarsAt(
        self: *const Screen,
        row: u16,
        col: u16,
        output: *[scalar_storage.maximum_scalars]u32,
    ) []const u32 {
        if (row >= self.rows or col >= self.cols) return &.{};
        const observed = self.cellInfoAt(row, col);
        const lead_row = row -| observed.y;
        const lead_col = col -| observed.x;
        const lead = self.cellInfoAt(lead_row, lead_col);
        if (lead.codepoint == 0) return &.{};
        output[0] = lead.codepoint;
        const direct: usize = @min(
            @as(usize, lead.combining_len),
            lead.combining.len,
        );
        @memcpy(output[1..][0..direct], lead.combining[0..direct]);
        const index = self.rowStart(lead_row) + lead_col;
        const tail = acceptedTail(&self.scalars.?, index, lead.combining_len);
        @memcpy(output[1 + direct ..][0..tail.len], tail);
        return output[0 .. 1 + direct + tail.len];
    }

    /// Return whether `col` is a configured stop, using default eight-column stops without storage.
    pub fn tabStopAt(self: *const Screen, col: u16) bool {
        return self.tab_stops.at(col);
    }

    /// Read history cell by recency index and column.
    pub fn historyRowAt(self: *const Screen, history_idx: u32, col: u16) u21 {
        return @intCast(self.historyCellAt(history_idx, col).codepoint);
    }

    /// Returns a copied history cell by recency, or a blank cell out of range.
    pub fn historyCellAt(self: *const Screen, history_idx: u32, col: u16) Cell {
        const h = self.history orelse return blank_cell;
        const bounded_idx: u32 = history_idx;
        if (bounded_idx >= self.history_count or col >= self.cols) return blank_cell;
        const slot = self.historySlotForRecency(history_idx) orelse return blank_cell;
        return h[@intCast(slot * @as(u32, self.cols) + @as(u32, col))];
    }

    /// Copies one complete retained-history lead scalar sequence.
    pub fn historyCellScalarsAt(
        self: *const Screen,
        history_idx: u32,
        col: u16,
        output: *[scalar_storage.maximum_scalars]u32,
    ) []const u32 {
        const slot = self.historySlotForRecency(history_idx) orelse return &.{};
        if (col >= self.cols) return &.{};
        const observed = self.historyCellAt(history_idx, col);
        const lead_col = col -| observed.x;
        const lead = self.historyCellAt(history_idx, lead_col);
        if (lead.codepoint == 0) return &.{};
        output[0] = lead.codepoint;
        const direct: usize = @min(
            @as(usize, lead.combining_len),
            lead.combining.len,
        );
        @memcpy(output[1..][0..direct], lead.combining[0..direct]);
        const index = slot * @as(u32, self.cols) + lead_col;
        const tail = acceptedTail(&self.history_scalars.?, index, lead.combining_len);
        @memcpy(output[1 + direct ..][0..tail.len], tail);
        return output[0 .. 1 + direct + tail.len];
    }

    /// Borrows one visible row from this screen bank.
    pub fn visibleRowCells(self: *const Screen, row: u16) []const Cell {
        std.debug.assert(row < self.rows);
        const cells = self.cells orelse unreachable;
        const start: usize = @intCast(self.rowStart(row));
        return cells[start..][0..self.cols];
    }

    /// Borrows one retained history row by newest-first recency.
    pub fn historyRowCells(self: *const Screen, history_idx: u32) []const Cell {
        std.debug.assert(history_idx < self.history_count);
        const cells = self.history orelse unreachable;
        const slot = self.historySlotForRecency(history_idx) orelse unreachable;
        const start: usize = @intCast(slot * @as(u32, self.cols));
        return cells[start..][0..self.cols];
    }

    /// Return retained history row count.
    pub fn historyCount(self: *const Screen) u32 {
        return self.history_count;
    }

    /// Returns the oldest projected history row identity.
    pub fn historyRowBase(self: *const Screen) u32 {
        return self.history_row_base;
    }

    /// Return configured history capacity.
    pub fn historyCapacity(self: *const Screen) u16 {
        return self.history_capacity;
    }

    // -------------------------------------------------------------------------
    // Action routing and cursor movement
    // -------------------------------------------------------------------------

    /// Apply one routed screen mutation request to this Screen.
    pub fn applyScreen(self: *Screen, event: Screen.Action) void {
        switch (event) {
            .cursor_up,
            .cursor_down,
            .cursor_forward,
            .cursor_back,
            .cursor_next_line,
            .cursor_prev_line,
            .cursor_horizontal_absolute,
            .cursor_vertical_absolute,
            .cursor_position,
            => self.applyCursorMove(event),
            .write_text, .write_codepoint => self.applyRetainedState(event),
            .line_feed,
            .next_line,
            .carriage_return,
            .backspace,
            .horizontal_tab,
            .horizontal_tab_forward,
            .horizontal_tab_back,
            => self.applyFlowMove(event),
            .horizontal_tab_set,
            .tab_clear_current,
            .tab_clear_all,
            .reset_default_tab_stops,
            => self.applyTabState(event),
            .cursor_visible,
            .cursor_style,
            .cursor_shape,
            .cursor_color,
            .cursor_text_color,
            .auto_wrap,
            .origin_mode,
            .insert_mode,
            .left_right_margin_mode,
            => self.applyScreenState(event),
            .hard_reset => self.applyLineEdit(event),
        }
    }

    fn applyCursorMove(self: *Screen, event: Screen.Action) void {
        self.wrap_pending = false;
        switch (event) {
            .cursor_up => |n| self.setCursorRowClamped(@max(self.cursor.row -| n, self.cursorTopBoundary())),
            .cursor_down => |n| self.setCursorRowClamped(@min(self.cursor.row +| n, self.cursorBottomBoundary())),
            .cursor_forward => |n| self.cursor.setColByClient(@min(self.cursor.col +| n, self.cursorRightBoundary())),
            .cursor_back => |n| self.cursor.setColByClient(@max(self.cursor.col -| n, self.cursorLeftBoundary())),
            .cursor_next_line => |n| self.cursor.setPositionByClient(
                @min(self.cursor.row +| n, self.cursorBottomBoundary()),
                self.relativeLineHomeCol(),
            ),
            .cursor_prev_line => |n| self.cursor.setPositionByClient(
                @max(self.cursor.row -| n, self.cursorTopBoundary()),
                self.relativeLineHomeCol(),
            ),
            .cursor_horizontal_absolute => |col| self.cursor.setColByClient(
                @min(self.resolveAbsoluteCol(col), self.lineRightBoundary(self.cursor.row)),
            ),
            .cursor_vertical_absolute => |row| {
                self.setCursorRowClamped(self.resolveAbsoluteRow(row));
                self.cursor.markAbsolutePositionTimestamp();
            },
            .cursor_position => |pos| {
                const row = @min(self.resolveAbsoluteRow(pos.row), self.rows -| 1);
                self.cursor.setPositionByClient(
                    row,
                    @min(self.resolveAbsoluteCol(pos.col), self.lineRightBoundary(row)),
                );
                self.cursor.markAbsolutePositionTimestamp();
            },
            else => unreachable,
        }
    }

    // Applies one cursor-positioning event and reports exact position or pending-wrap mutation.
    /// Applies one cursor-motion action and reports semantic change.
    pub fn moveCursor(self: *Screen, event: Screen.Action) bool {
        const cursor_before = self.cursor;
        const wrap_before = self.wrap_pending;
        self.applyCursorMove(event);
        return !std.meta.eql(cursor_before, self.cursor) or wrap_before != self.wrap_pending;
    }

    fn applyRetainedState(self: *Screen, event: Screen.Action) void {
        switch (event) {
            .write_text => |text| self.writeText(text),
            .write_codepoint => |codepoint| self.writeCell(codepoint),
            else => unreachable,
        }
    }

    fn applyFlowMove(self: *Screen, event: Screen.Action) void {
        self.wrap_pending = false;
        switch (event) {
            .line_feed => {
                self.setRowWrapped(self.cursor.row, false);
                self.lineFeed();
            },
            .next_line => {
                self.setRowWrapped(self.cursor.row, false);
                self.cursor.setColByClient(0);
                self.lineFeed();
            },
            .carriage_return => self.cursor.setColByClient(0),
            .backspace => self.applyBackspace(false),
            .horizontal_tab => self.horizontalTabForward(1),
            .horizontal_tab_forward => |count| self.horizontalTabForward(count),
            .horizontal_tab_back => |count| self.horizontalTabBack(count),
            else => unreachable,
        }
    }

    fn applyTabState(self: *Screen, event: Screen.Action) void {
        switch (event) {
            .horizontal_tab_set => self.tab_stops.set(self.cursor.col),
            .tab_clear_current => self.tab_stops.clear(self.cursor.col),
            .tab_clear_all => self.tab_stops.clearAll(),
            .reset_default_tab_stops => self.tab_stops.reset(),
            else => unreachable,
        }
    }

    // Applies iTerm2's reverse-wrap policy to one C0 BS and reports exact cursor or phantom mutation.
    /// Applies backspace with the terminal-selected reverse-wrap mode.
    pub fn backspace(self: *Screen, reverse_wraparound: bool) bool {
        const cursor_before = self.cursor;
        const pending_before = self.wrap_pending;
        self.applyBackspace(reverse_wraparound);
        return !std.meta.eql(cursor_before, self.cursor) or pending_before != self.wrap_pending;
    }

    fn applyBackspace(self: *Screen, reverse_wraparound: bool) void {
        if (self.wrap_pending) {
            self.wrap_pending = false;
            if (!reverse_wraparound or !self.auto_wrap) {
                self.cursor.setColByClient(self.cursor.col -| 1);
            }
        } else if (self.shouldReverseWrap(reverse_wraparound)) {
            const previous_row = self.cursor.row - 1;
            const right = if (self.left_right_margin_mode)
                @min(self.right_margin, self.lineRightBoundary(previous_row))
            else
                self.lineRightBoundary(previous_row);
            self.cursor.setPositionByClient(previous_row, right);
        } else {
            const left = if (self.left_right_margin_mode) self.left_margin else 0;
            if (self.cursor.col > left or (self.cursor.col < left and self.cursor.col > 0)) {
                self.cursor.setColByClient(self.cursor.col - 1);
            }
        }
    }

    fn shouldReverseWrap(self: *const Screen, reverse_wraparound: bool) bool {
        if (!self.auto_wrap) return false;
        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        if (self.cursor.col != left and self.cursor.col != 0) return false;
        if (self.cursor.row == 0 or self.cursor.row == self.scroll_top) return false;
        if (reverse_wraparound) return true;
        return !self.left_right_margin_mode and self.rowWrapped(self.cursor.row - 1);
    }

    fn applyScreenState(self: *Screen, event: Screen.Action) void {
        switch (event) {
            .cursor_visible => |visible| self.cursor.visible = visible,
            .cursor_style => |cursor_style| switch (cursor_style) {
                .restore_default => self.cursor.restoreDefaultStyle(),
                .program_override => |style| self.cursor.setProgramStyle(style),
            },
            .cursor_shape => |shape| self.cursor.setProgramShape(shape),
            .cursor_color => |value| self.cursor.cursor_color = value,
            .cursor_text_color => |value| self.cursor.cursor_text_color = value,
            .auto_wrap => |enabled| {
                self.auto_wrap = enabled;
                if (!enabled) self.wrap_pending = false;
            },
            .origin_mode => |enabled| {
                self.origin_mode = enabled;
                self.wrap_pending = false;
                self.cursor.setPositionByClient(if (enabled) self.scroll_top else 0, self.lineHomeCol());
            },
            .insert_mode => |enabled| self.insert_mode = enabled,
            .left_right_margin_mode => |enabled| {
                if (self.setLeftRightMarginMode(enabled)) return;
            },
            else => unreachable,
        }
    }

    fn applyLineEdit(self: *Screen, event: Screen.Action) void {
        switch (event) {
            .hard_reset => self.reset(),
            else => unreachable,
        }
    }

    // -------------------------------------------------------------------------
    // Erase, rectangular, line, and column editing
    // -------------------------------------------------------------------------

    /// Erases one display mode, preserving protected cells when requested.
    /// Returns whether cells, row state, history, or pending wrap changed; it cannot fail.
    pub fn eraseDisplay(self: *Screen, mode: EraseMode, protected: bool) bool {
        var changed = self.cancelPendingWrap();
        if (self.cells == null) return changed;
        if (self.rows == 0 or self.cols == 0) return changed;
        switch (mode) {
            .cursor_to_end => {
                changed = self.clearDisplayRowRange(
                    protected,
                    self.cursor.row,
                    self.cursor.col,
                    self.lineColumnCount(self.cursor.row),
                ) or changed;
                if (self.cursor.col < self.lineColumnCount(self.cursor.row)) {
                    changed = self.clearRowContinuation(self.cursor.row) or changed;
                }
                var row = self.cursor.row + 1;
                while (row < self.rows) : (row += 1) {
                    changed = self.eraseFullDisplayRow(row, protected) or changed;
                }
            },
            .start_to_cursor => {
                var row: u16 = 0;
                while (row < self.cursor.row) : (row += 1) {
                    changed = self.eraseFullDisplayRow(row, protected) or changed;
                }
                changed = self.clearDisplayRowRange(protected, self.cursor.row, 0, self.cursor.col + 1) or changed;
            },
            .all => {
                var row: u16 = 0;
                while (row < self.rows) : (row += 1) {
                    changed = self.eraseFullDisplayRow(row, protected) or changed;
                }
            },
            .scrollback => return self.clearScrollback() or changed,
        }
        return changed;
    }

    fn clearDisplayRowRange(self: *Screen, protected: bool, row: u16, start_col: u16, end_col_exclusive: u16) bool {
        return self.eraseRowRange(row, start_col, end_col_exclusive, protected);
    }

    fn eraseFullDisplayRow(self: *Screen, row: u16, protected: bool) bool {
        var changed = self.clearDisplayRowRange(protected, row, 0, self.lineColumnCount(row));
        changed = self.clearRowContinuation(row) or changed;
        if (self.lineGeometry(row) != .single_width) {
            self.resetLineGeometry(row);
            changed = true;
        }
        return changed;
    }

    /// Cancels latent autowrap and reports whether it was pending.
    pub fn cancelPendingWrap(self: *Screen) bool {
        const changed = self.wrap_pending;
        self.wrap_pending = false;
        return changed;
    }

    // Row continuation is published metadata, so changing it dirties the complete row.
    fn clearRowContinuation(self: *Screen, row: u16) bool {
        if (!self.rowWrapped(row)) return false;
        self.setRowWrapped(row, false);
        return true;
    }

    /// Set the hyperlink identity copied into subsequent cells and report exact mutation.
    /// Selects the hyperlink identity stored by subsequent cells.
    pub fn setCurrentLinkId(self: *Screen, link_id: u32) bool {
        if (self.current_attrs.link_id == link_id) return false;
        self.current_attrs.link_id = link_id;
        return true;
    }

    /// Resolve a zero-based row against the active origin region, saturating at its bottom.
    fn resolveAbsoluteRow(self: *const Screen, row: u16) u16 {
        if (!self.origin_mode) return row;
        const bottom = if (self.rows == 0) 0 else @min(self.scroll_bottom, self.rows - 1);
        const region_len = bottom - self.scroll_top;
        return self.scroll_top + @min(row, region_len);
    }

    /// Resolve a zero-based column against active origin-mode horizontal margins.
    fn resolveAbsoluteCol(self: *const Screen, col: u16) u16 {
        if (!(self.origin_mode and self.left_right_margin_mode)) return col;
        const region_len = self.right_margin - self.left_margin;
        return self.left_margin + @min(col, region_len);
    }

    /// Return the line-home column selected by origin and horizontal-margin modes.
    fn lineHomeCol(self: *const Screen) u16 {
        return if (self.origin_mode and self.left_right_margin_mode) self.left_margin else 0;
    }

    fn relativeLineHomeCol(self: *const Screen) u16 {
        return if (self.left_right_margin_mode) self.left_margin else 0;
    }

    // Relative movement follows iTerm2's directional margin rule: movement toward an active
    // margin stops there even when starting beyond the opposite margin.
    fn cursorTopBoundary(self: *const Screen) u16 {
        return if (self.cursor.row >= self.scroll_top) self.scroll_top else 0;
    }

    fn cursorBottomBoundary(self: *const Screen) u16 {
        const bottom = self.scrollBottom();
        return if (self.cursor.row <= bottom) bottom else self.rows -| 1;
    }

    fn cursorLeftBoundary(self: *const Screen) u16 {
        if (!self.left_right_margin_mode) return 0;
        if (self.cursor.col >= self.left_margin) return self.left_margin;
        return 0;
    }

    fn cursorRightBoundary(self: *const Screen) u16 {
        const line_right = self.lineRightBoundary(self.cursor.row);
        if (!self.left_right_margin_mode) return line_right;
        return if (self.cursor.col <= self.right_margin) @min(self.right_margin, line_right) else line_right;
    }

    /// Clears visible cells and marks the complete screen dirty.
    /// Clears the visible grid without discarding retained history.
    pub fn clearVisibleCells(self: *Screen) void {
        if (self.cells) |cells| @memset(cells, blank_cell);
        if (self.scalars) |*storage| storage.clearAll();
        if (self.row_flags) |flags| @memset(flags, 0);
    }

    /// Moves the alternate-screen cursor to origin and clears pending wrap.
    pub fn resetCursorForAltEntry(self: *Screen) void {
        self.cursor.resetForAltEntry();
        self.wrap_pending = false;
        self.current_attrs = initial_cell_attrs;
    }

    /// Supplies the monotonic timestamp available to an absolute-position
    /// command parsed in the next terminal feed.
    pub fn setCursorMovementTimestamp(self: *Screen, timestamp_ns: u64) void {
        self.cursor.setMovementTimestamp(timestamp_ns);
    }

    /// Returns the monotonic timestamp of the latest absolute-position command.
    pub fn cursorMovementTimestamp(self: *const Screen) u64 {
        return self.cursor.position_changed_timestamp_ns;
    }

    /// Return the active horizontal editing boundary on the left.
    /// Returns the effective left margin for cursor motion.
    pub fn leftBoundary(self: *const Screen) u16 {
        return if (self.left_right_margin_mode) self.left_margin else 0;
    }

    /// Return the active horizontal editing boundary on the right.
    /// Returns the effective right margin for cursor motion.
    pub fn rightBoundary(self: *const Screen) u16 {
        return if (self.left_right_margin_mode)
            @min(self.right_margin, self.lineRightBoundary(self.cursor.row))
        else
            self.lineRightBoundary(self.cursor.row);
    }

    /// Returns the effective right boundary for one physical row.
    pub fn lineRightBoundary(self: *const Screen, row: u16) u16 {
        return self.lineColumnCount(row) -| 1;
    }

    fn setCursorRowClamped(self: *Screen, row: u16) void {
        const bounded_row = @min(row, self.rows -| 1);
        self.cursor.setPositionByClient(
            bounded_row,
            @min(self.cursor.col, self.lineRightBoundary(bounded_row)),
        );
    }

    /// Clears retained scrollback while preserving the visible grid.
    pub fn clearScrollback(self: *Screen) bool {
        const changed = self.history_count != 0;
        self.dropOldestProjectedRows(self.history_count);
        std.debug.assert(self.history_count == 0);
        std.debug.assert(self.history_write_idx == 0);
        return changed;
    }

    /// Stores one nonzero caller cell-pixel size for terminal protocol reports.
    pub fn setCellPixelSize(self: *Screen, width: u32, height: u32) void {
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);
        self.cell_pixel_size = .{ .width = width, .height = height };
    }

    /// Returns configured nonzero cell pixels, when supplied by the embedding caller.
    pub fn cellPixelSize(self: *const Screen) ?CellPixelSize {
        return self.cell_pixel_size;
    }

    /// Erases one active-line mode, preserving protected cells when `selective` is set.
    /// Returns whether cells, continuation, or pending wrap changed; it cannot fail.
    pub fn eraseLine(self: *Screen, mode: EraseMode, selective: bool) bool {
        var changed = self.cancelPendingWrap();
        if (self.cells == null) return changed;
        if (self.rows == 0 or self.cols == 0) return changed;
        const line_cols = self.lineColumnCount(self.cursor.row);
        const range: [2]u16 = switch (mode) {
            .cursor_to_end => .{ self.cursor.col, line_cols },
            .start_to_cursor => .{ @as(u16, 0), self.cursor.col + 1 },
            .all => .{ @as(u16, 0), line_cols },
            .scrollback => return changed,
        };
        changed = self.eraseRowRange(self.cursor.row, range[0], range[1], selective) or changed;
        if (mode == .all or mode == .cursor_to_end) {
            if (range[1] == line_cols) {
                changed = self.clearRowContinuation(self.cursor.row) or changed;
            }
        }
        return changed;
    }

    /// Erases at least one character through the logical row edge.
    /// Returns whether cells, continuation, or pending wrap changed; it cannot fail.
    pub fn eraseChars(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0) return changed;
        const line_cols = self.lineColumnCount(self.cursor.row);
        if (self.cursor.col >= line_cols) return changed;
        const amount = @min(@max(count, 1), line_cols - self.cursor.col);
        changed = self.eraseRowRange(self.cursor.row, self.cursor.col, self.cursor.col + amount, false) or changed;
        if (self.cursor.col + amount == line_cols) {
            changed = self.clearRowContinuation(self.cursor.row) or changed;
        }
        return changed;
    }

    /// Select ISO, DEC, or unprotected provenance for subsequently written cells.
    /// Returns false when the retained protection state is already identical.
    pub fn setCharacterProtection(self: *Screen, protection: ScreenProtection) bool {
        if (self.current_attrs.protected == protection) return false;
        self.current_attrs.protected = protection;
        return true;
    }

    /// Select rectangular or stream extent for subsequent rectangle-attribute changes.
    /// Returns false when the retained extent is already identical.
    pub fn setRectAttrExtent(self: *Screen, rectangular: bool) bool {
        if (self.attr_change_extent_rect == rectangular) return false;
        self.attr_change_extent_rect = rectangular;
        return true;
    }

    /// Change attributes in the clipped rectangle using rectangular or stream extent.
    /// Returns exact cell-attribute or pending-wrap mutation.
    pub fn changeRectAttrs(self: *Screen, area: RectArea, attrs: []const u16, reverse: bool) bool {
        var changed = self.cancelPendingWrap();
        const cells = self.cells orelse return changed;
        if (attrs.len == 0) return changed;
        const bounds = self.rectBounds(area) orelse return changed;
        changed = self.clearClustersIntersecting(
            bounds.top,
            bounds.bottom + 1,
            bounds.left,
            bounds.right + 1,
        ) or changed;
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            const row_start = self.rowStart(row);
            const start_col = if (self.attr_change_extent_rect or row == bounds.top) bounds.left else 0;
            const end_col = if (self.attr_change_extent_rect or row == bounds.bottom) bounds.right else self.cols -| 1;
            var col = start_col;
            while (col <= end_col) : (col += 1) {
                const idx = row_start + @as(u32, col);
                if (applyRectAttrOps(&cells[@intCast(idx)].attrs, attrs, reverse)) {
                    changed = true;
                }
            }
        }
        return changed;
    }

    /// Erase one clipped rectangle under ISO or DEC protection rules.
    /// Returns exact cell, row-continuation, or pending-wrap mutation.
    pub fn eraseRect(self: *Screen, area: RectArea, selective: bool) bool {
        var changed = self.cancelPendingWrap();
        const bounds = self.rectBounds(area) orelse return changed;
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            changed = self.eraseRowRange(row, bounds.left, bounds.right + 1, selective) or changed;
            if (bounds.left == 0 and bounds.right + 1 == self.cols) {
                changed = self.clearRowContinuation(row) or changed;
            }
        }
        return changed;
    }

    /// Fill a clipped rectangle with `codepoint` and the current write attributes.
    /// Returns exact cell or pending-wrap mutation.
    pub fn fillRect(self: *Screen, area: RectArea, codepoint: u21) bool {
        var changed = self.cancelPendingWrap();
        const cells = self.cells orelse return changed;
        const bounds = self.rectBounds(area) orelse return changed;
        changed = self.clearClustersIntersecting(
            bounds.top,
            bounds.bottom + 1,
            bounds.left,
            bounds.right + 1,
        ) or changed;
        const fill = Cell{ .codepoint = codepoint, .attrs = self.current_attrs };
        var row = bounds.top;
        while (row <= bounds.bottom) : (row += 1) {
            const start = self.rowStart(row);
            var col = bounds.left;
            while (col <= bounds.right) : (col += 1) {
                const cell = &cells[start + col];
                if (std.meta.eql(cell.*, fill)) continue;
                clearAcceptedTail(&self.scalars.?, start + col, cell.combining_len);
                cell.* = fill;
                changed = true;
            }
        }
        return changed;
    }

    /// Copy one clipped page-one rectangle in overlap-safe row and column order.
    ///
    /// Unsupported pages and missing storage leave the destination unchanged.
    /// Returns exact destination-cell or pending-wrap mutation.
    pub fn copyRect(self: *Screen, request: RectCopy) bool {
        var changed = self.cancelPendingWrap();
        const cells = self.cells orelse return changed;
        if (request.source_page != 1 or request.dest_page != 1) return changed;
        const source = self.rectBounds(request.area) orelse return changed;
        const origin = self.activeOriginBounds();
        const dest_top = origin.top + @min(request.dest_top, origin.bottom - origin.top);
        const dest_left = origin.left + @min(request.dest_left, origin.right - origin.left);
        const height: u16 = source.bottom - source.top + 1;
        const width: u16 = source.right - source.left + 1;
        const copy_height = @min(height, origin.bottom - dest_top + 1);
        const copy_width = @min(width, origin.right - dest_left + 1);
        if (copy_height == 0 or copy_width == 0) return changed;
        var source_row = source.top;
        while (source_row < source.top + copy_height) : (source_row += 1) {
            var source_col = source.left;
            while (source_col < source.left + copy_width) : (source_col += 1) {
                const source_cell = cells[@intCast(self.rowStart(source_row) + source_col)];
                if (source_cell.width != 1 or source_cell.height != 1 or
                    source_cell.x != 0 or source_cell.y != 0)
                    return changed;
            }
        }
        changed = self.clearClustersIntersecting(
            dest_top,
            dest_top + copy_height,
            dest_left,
            dest_left + copy_width,
        ) or changed;

        var copied_rows: u16 = 0;
        while (copied_rows < copy_height) : (copied_rows += 1) {
            const row = if (dest_top > source.top) copy_height - copied_rows - 1 else copied_rows;
            const source_start = self.rowStart(source.top + row) + source.left;
            const dest_start = self.rowStart(dest_top + row) + dest_left;
            const source_cells = cells[@intCast(source_start)..@intCast(source_start + copy_width)];
            const dest_cells = cells[@intCast(dest_start)..@intCast(dest_start + copy_width)];
            for (dest_cells, source_cells) |dest, source_cell| {
                if (std.meta.eql(dest, source_cell)) continue;
                changed = true;
            }
            if (dest_start > source_start) {
                std.mem.copyBackwards(Cell, dest_cells, source_cells);
            } else {
                std.mem.copyForwards(Cell, dest_cells, source_cells);
            }
        }
        return changed;
    }

    /// Inserts columns from the cursor through the active right margin across the vertical region.
    /// Returns exact cell, continuation, or pending-wrap mutation; an outside cursor changes no rows.
    pub fn insertColumns(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        const bottom = self.scrollBottom();
        if (self.rows == 0 or self.cols == 0 or self.scroll_top > bottom) return changed;
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) changed = self.insertColumnsInRow(row, count) or changed;
        return changed;
    }

    /// Deletes columns from the cursor through the active right margin across the vertical region.
    /// Returns exact cell, continuation, or pending-wrap mutation; an outside cursor changes no rows.
    pub fn deleteColumns(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        const bottom = self.scrollBottom();
        if (self.rows == 0 or self.cols == 0 or self.scroll_top > bottom) return changed;
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) changed = self.deleteColumnsInRow(row, count) or changed;
        return changed;
    }

    /// Shift active scroll-region rows left within current horizontal boundaries.
    /// Returns exact cell, continuation, or pending-wrap mutation.
    pub fn shiftColumnsLeft(self: *Screen, count: u16) bool {
        const changed = self.cancelPendingWrap();
        return self.shiftColumnsLeftInBounds(count, self.leftBoundary(), self.rightBoundary()) or changed;
    }

    /// Shift active scroll-region rows right within current horizontal boundaries.
    /// Returns exact cell, continuation, or pending-wrap mutation.
    pub fn shiftColumnsRight(self: *Screen, count: u16) bool {
        const changed = self.cancelPendingWrap();
        return self.shiftColumnsRightInBounds(count, self.leftBoundary(), self.rightBoundary()) or changed;
    }

    fn shiftColumnsLeftInBounds(self: *Screen, count: u16, left: u16, right: u16) bool {
        const bottom = self.scrollBottom();
        if (self.cols == 0 or left > right or right >= self.cols or self.scroll_top > bottom) return false;
        var changed = false;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) changed = self.shiftRowLeft(row, count, left, right) or changed;
        return changed;
    }

    fn shiftColumnsRightInBounds(self: *Screen, count: u16, left: u16, right: u16) bool {
        const bottom = self.scrollBottom();
        if (self.cols == 0 or left > right or right >= self.cols or self.scroll_top > bottom) return false;
        var changed = false;
        var row = self.scroll_top;
        while (row <= bottom) : (row += 1) changed = self.shiftRowRight(row, count, left, right) or changed;
        return changed;
    }

    /// Insert at least one erase cell at the cursor within the right boundary.
    /// Returns exact cell, continuation, or pending-wrap mutation.
    pub fn insertChars(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0) return changed;
        if (self.cursor.col >= self.cols) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;

        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
        changed = self.clearClustersIntersecting(
            self.cursor.row,
            self.cursor.row + 1,
            self.cursor.col,
            self.rightBoundary() + 1,
        ) or changed;
        const row = self.rowCells(self.cursor.row) orelse return changed;
        const src_col = screenColCount(self.cursor.col);
        const dst_col = src_col + screenColCount(amount);
        const move_len = screenColCount(self.rightBoundary() + 1) - dst_col;

        std.debug.assert(src_col <= dst_col);
        std.debug.assert(dst_col <= screenColCount(self.rightBoundary() + 1));
        std.debug.assert(dst_col + move_len == screenColCount(self.rightBoundary() + 1));
        std.debug.assert(src_col + move_len <= row.len);
        std.debug.assert(dst_col + move_len <= row.len);
        std.debug.assert(src_col + screenColCount(amount) <= row.len);

        const erase = self.eraseCell();
        var cells_changed = false;
        var col = src_col;
        const end = screenColCount(self.rightBoundary() + 1);
        while (col < end) : (col += 1) {
            const replacement = if (col < dst_col) erase else row[@intCast(col - screenColCount(amount))];
            if (!std.meta.eql(row[@intCast(col)], replacement)) cells_changed = true;
        }
        if (move_len > 0) {
            const base = self.rowStart(self.cursor.row);
            self.moveScalarCells(
                base + dst_col,
                base + src_col,
                move_len,
                true,
            );
            std.mem.copyBackwards(
                Cell,
                row[@intCast(dst_col)..@intCast(dst_col + move_len)],
                row[@intCast(src_col)..@intCast(src_col + move_len)],
            );
        }
        self.clearScalarCells(
            self.rowStart(self.cursor.row) + src_col,
            screenColCount(amount),
        );
        @memset(row[@intCast(src_col)..@intCast(src_col + screenColCount(amount))], erase);
        cells_changed = self.clearRowContinuation(self.cursor.row) or cells_changed;
        return cells_changed or changed;
    }

    /// Delete at least one cell at the cursor within the right boundary.
    /// Returns exact cell, continuation, or pending-wrap mutation.
    pub fn deleteChars(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0) return changed;
        if (self.cursor.col >= self.cols) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;

        const amount = @min(@max(count, 1), self.rightBoundary() - self.cursor.col + 1);
        changed = self.clearClustersIntersecting(
            self.cursor.row,
            self.cursor.row + 1,
            self.cursor.col,
            self.rightBoundary() + 1,
        ) or changed;
        const row = self.rowCells(self.cursor.row) orelse return changed;
        const dst_col = screenColCount(self.cursor.col);
        const src_col = @min(dst_col + screenColCount(amount), screenColCount(self.rightBoundary() + 1));
        const move_len = screenColCount(self.rightBoundary() + 1) - src_col;
        const tail_start = screenColCount(self.rightBoundary() + 1) - screenColCount(amount);
        const tail_end = screenColCount(self.rightBoundary() + 1);

        std.debug.assert(dst_col <= src_col);
        std.debug.assert(src_col <= tail_end);
        std.debug.assert(src_col + move_len == tail_end);
        std.debug.assert(dst_col + move_len <= row.len);
        std.debug.assert(src_col + move_len <= row.len);
        std.debug.assert(tail_start <= tail_end);
        std.debug.assert(tail_end <= row.len);

        const erase = self.eraseCell();
        var cells_changed = false;
        var col = dst_col;
        while (col < tail_end) : (col += 1) {
            const replacement = if (col < tail_start) row[@intCast(col + screenColCount(amount))] else erase;
            if (!std.meta.eql(row[@intCast(col)], replacement)) cells_changed = true;
        }
        if (move_len > 0) {
            const base = self.rowStart(self.cursor.row);
            self.moveScalarCells(base + dst_col, base + src_col, move_len, false);
            std.mem.copyForwards(
                Cell,
                row[@intCast(dst_col)..@intCast(dst_col + move_len)],
                row[@intCast(src_col)..@intCast(src_col + move_len)],
            );
        }
        self.clearScalarCells(
            self.rowStart(self.cursor.row) + tail_start,
            screenColCount(amount),
        );
        @memset(row[@intCast(tail_start)..@intCast(tail_end)], erase);
        cells_changed = self.clearRowContinuation(self.cursor.row) or cells_changed;
        return cells_changed or changed;
    }

    fn insertColumnsInRow(self: *Screen, row: u16, count: u16) bool {
        const line_cols = self.lineColumnCount(row);
        const line_right = line_cols - 1;
        const right = if (self.left_right_margin_mode) @min(self.right_margin, line_right) else line_right;
        if (self.cursor.col > right) return false;
        const amount = @min(@max(count, 1), right - self.cursor.col + 1);
        var changed = self.clearClustersIntersecting(row, row + 1, self.cursor.col, right + 1);
        const amount_cols = screenColCount(amount);
        const cells = self.rowCells(row) orelse return false;
        const cursor_col = screenColCount(self.cursor.col);
        const dst_col = cursor_col + amount_cols;
        const end = screenColCount(right + 1);
        const move_len = end - dst_col;
        const erase = self.eraseCell();
        var col = cursor_col;
        while (col < end) : (col += 1) {
            const replacement = if (col < dst_col) erase else cells[@intCast(col - amount_cols)];
            if (!std.meta.eql(cells[@intCast(col)], replacement)) changed = true;
        }

        std.debug.assert(cursor_col <= dst_col);
        std.debug.assert(dst_col <= end);
        std.debug.assert(dst_col + move_len == end);
        std.debug.assert(cursor_col + move_len <= cells.len);
        std.debug.assert(dst_col + move_len <= cells.len);
        std.debug.assert(cursor_col + amount_cols <= cells.len);

        if (move_len > 0) {
            const base = self.rowStart(row);
            self.moveScalarCells(
                base + dst_col,
                base + cursor_col,
                move_len,
                true,
            );
            std.mem.copyBackwards(
                Cell,
                cells[@intCast(dst_col)..@intCast(dst_col + move_len)],
                cells[@intCast(cursor_col)..@intCast(cursor_col + move_len)],
            );
        }
        self.clearScalarCells(
            self.rowStart(row) + cursor_col,
            amount_cols,
        );
        @memset(cells[@intCast(cursor_col)..@intCast(cursor_col + amount_cols)], erase);
        changed = self.clearRowContinuation(row) or changed;
        return changed;
    }

    fn deleteColumnsInRow(self: *Screen, row: u16, count: u16) bool {
        const line_cols = self.lineColumnCount(row);
        const line_right = line_cols - 1;
        const right = if (self.left_right_margin_mode) @min(self.right_margin, line_right) else line_right;
        if (self.cursor.col > right) return false;
        const amount = @min(@max(count, 1), right - self.cursor.col + 1);
        var changed = self.clearClustersIntersecting(row, row + 1, self.cursor.col, right + 1);
        const amount_cols = screenColCount(amount);
        const cells = self.rowCells(row) orelse return false;
        const cursor_col = screenColCount(self.cursor.col);
        const end = screenColCount(right + 1);
        const src_col = cursor_col + amount_cols;
        const move_len = end - src_col;
        const tail_start = end - amount_cols;
        const erase = self.eraseCell();
        var col = cursor_col;
        while (col < end) : (col += 1) {
            const replacement = if (col < tail_start) cells[@intCast(col + amount_cols)] else erase;
            if (!std.meta.eql(cells[@intCast(col)], replacement)) changed = true;
        }

        std.debug.assert(cursor_col <= src_col);
        std.debug.assert(src_col <= end);
        std.debug.assert(src_col + move_len == end);
        std.debug.assert(cursor_col + move_len <= cells.len);
        std.debug.assert(src_col + move_len <= cells.len);

        if (move_len > 0) {
            const base = self.rowStart(row);
            self.moveScalarCells(
                base + cursor_col,
                base + src_col,
                move_len,
                false,
            );
            std.mem.copyForwards(
                Cell,
                cells[@intCast(cursor_col)..@intCast(cursor_col + move_len)],
                cells[@intCast(src_col)..@intCast(src_col + move_len)],
            );
        }
        self.clearScalarCells(
            self.rowStart(row) + tail_start,
            amount_cols,
        );
        @memset(
            cells[@intCast(tail_start)..@intCast(end)],
            erase,
        );
        changed = self.clearRowContinuation(row) or changed;
        return changed;
    }

    fn shiftRowLeft(self: *Screen, row: u16, count: u16, left: u16, right: u16) bool {
        if (left > right or right >= self.cols) return false;

        var changed = self.clearClustersIntersecting(row, row + 1, left, right + 1);
        const width = right - left + 1;
        const amount = @min(@max(count, 1), width);
        const cells = self.rowCells(row) orelse return false;
        const left_idx = screenColCount(left);
        const move_len = screenColCount(width - amount);
        const end = left_idx + screenColCount(width);
        const erase = self.eraseCell();
        var col = left_idx;
        while (col < end) : (col += 1) {
            const replacement = if (col < left_idx + move_len)
                cells[@intCast(col + screenColCount(amount))]
            else
                erase;
            if (!std.meta.eql(cells[@intCast(col)], replacement)) changed = true;
        }

        std.debug.assert(width > 0);
        std.debug.assert(amount <= width);
        std.debug.assert(right + 1 <= self.cols);
        std.debug.assert(left_idx + screenColCount(width) <= cells.len);
        std.debug.assert(left_idx + screenColCount(amount) + move_len <= cells.len);
        std.debug.assert(left_idx + move_len <= left_idx + screenColCount(width));

        if (move_len > 0) {
            const source_start = left_idx + screenColCount(amount);
            const base = self.rowStart(row);
            self.moveScalarCells(
                base + left_idx,
                base + source_start,
                move_len,
                false,
            );
            std.mem.copyForwards(
                Cell,
                cells[@intCast(left_idx)..@intCast(left_idx + move_len)],
                cells[@intCast(source_start)..@intCast(source_start + move_len)],
            );
        }
        self.clearScalarCells(
            self.rowStart(row) + left_idx + move_len,
            screenColCount(amount),
        );
        @memset(cells[@intCast(left_idx + move_len)..@intCast(end)], erase);
        changed = self.clearRowContinuation(row) or changed;
        return changed;
    }

    fn shiftRowRight(self: *Screen, row: u16, count: u16, left: u16, right: u16) bool {
        if (left > right or right >= self.cols) return false;

        var changed = self.clearClustersIntersecting(row, row + 1, left, right + 1);
        const width = right - left + 1;
        const amount = @min(@max(count, 1), width);
        const cells = self.rowCells(row) orelse return false;
        const left_idx = screenColCount(left);
        const move_len = screenColCount(width - amount);
        const amount_cols = screenColCount(amount);
        const end = left_idx + screenColCount(width);
        const erase = self.eraseCell();
        var col = left_idx;
        while (col < end) : (col += 1) {
            const replacement = if (col < left_idx + amount_cols) erase else cells[@intCast(col - amount_cols)];
            if (!std.meta.eql(cells[@intCast(col)], replacement)) changed = true;
        }

        std.debug.assert(width > 0);
        std.debug.assert(amount <= width);
        std.debug.assert(right + 1 <= self.cols);
        std.debug.assert(left_idx + screenColCount(width) <= cells.len);
        std.debug.assert(left_idx + screenColCount(amount) + move_len <= cells.len);
        std.debug.assert(left_idx + screenColCount(amount) <= left_idx + screenColCount(width));

        if (move_len > 0) {
            const destination_start = left_idx + amount_cols;
            const base = self.rowStart(row);
            self.moveScalarCells(
                base + destination_start,
                base + left_idx,
                move_len,
                true,
            );
            std.mem.copyBackwards(
                Cell,
                cells[@intCast(destination_start)..@intCast(destination_start + move_len)],
                cells[@intCast(left_idx)..@intCast(left_idx + move_len)],
            );
        }
        self.clearScalarCells(
            self.rowStart(row) + left_idx,
            amount_cols,
        );
        @memset(cells[@intCast(left_idx)..@intCast(left_idx + amount_cols)], erase);
        changed = self.clearRowContinuation(row) or changed;
        return changed;
    }

    // -------------------------------------------------------------------------
    // Cell and scalar mutation support
    // -------------------------------------------------------------------------

    fn rowCells(self: *Screen, row: u16) ?[]Cell {
        const cells = self.cells orelse return null;
        const start = self.rowStart(row);
        std.debug.assert(row < self.rows);
        std.debug.assert(start + screenColCount(self.cols) <= cells.len);
        return cells[@intCast(start)..@intCast(start + screenColCount(self.cols))];
    }

    fn clearScalarCells(self: *Screen, start: u32, count: u32) void {
        const storage = if (self.scalars) |*value| value else return;
        const cells = self.cells orelse return;
        var index = start;
        while (index < start + count) : (index += 1)
            clearAcceptedTail(storage, index, cells[index].combining_len);
    }

    fn moveScalarCells(
        self: *Screen,
        destination: u32,
        source: u32,
        count: u32,
        backwards: bool,
    ) void {
        const storage = if (self.scalars) |*value| value else return;
        const cells = self.cells orelse return;
        var preflight: u32 = 0;
        while (preflight < count) : (preflight += 1) {
            const source_count = storage.validate(
                source + preflight,
                cells[source + preflight].combining_len,
            ) catch @panic("accepted source scalar mismatch");
            const destination_count = storage.validate(
                destination + preflight,
                cells[destination + preflight].combining_len,
            ) catch @panic("accepted destination scalar mismatch");
            if (source_count > scalar_storage.maximum_tail_scalars or
                destination_count > scalar_storage.maximum_tail_scalars)
                unreachable;
        }
        if (backwards) {
            var remaining = count;
            while (remaining != 0) {
                remaining -= 1;
                storage.move(
                    source + remaining,
                    cells[source + remaining].combining_len,
                    destination + remaining,
                    cells[destination + remaining].combining_len,
                ) catch unreachable;
            }
        } else {
            var index: u32 = 0;
            while (index < count) : (index += 1)
                storage.move(
                    source + index,
                    cells[source + index].combining_len,
                    destination + index,
                    cells[destination + index].combining_len,
                ) catch unreachable;
        }
    }

    // -------------------------------------------------------------------------
    // Text and grapheme admission
    // -------------------------------------------------------------------------

    /// Write one byte per cell through the terminal's graphic write path.
    pub fn writeText(self: *Screen, text: []const u8) void {
        for (text) |byte| self.writeCell(@intCast(byte));
    }

    /// Applies one Unicode scalar and reports exact accepted semantic mutation.
    pub fn writeCodepoint(self: *Screen, codepoint: u21) bool {
        return self.writeCellDisposition(codepoint);
    }

    /// Repeat the complete bounded preceding glyph using the current rendition.
    ///
    /// A zero count has the protocol default of one. The result is false when
    /// no preceding graphic exists or when scalar pressure prevents the first
    /// replay; true means at least one complete repetition committed. Accepted
    /// repetition owns its ordinary wrapping, insertion, and dirty state.
    pub fn repeatPreceding(self: *Screen, count: u16) bool {
        const graphic = self.last_graphic orelse return false;
        var remaining = @max(count, 1);
        var committed = false;
        while (remaining > 0) : (remaining -= 1) {
            if (!self.writeRepeatedGraphic(graphic)) break;
            committed = true;
        }
        return committed;
    }

    fn writeRepeatedGraphic(self: *Screen, graphic: LastGraphic) bool {
        if (self.cols == 0 or self.rows == 0) return false;
        const direct = @min(
            @as(usize, graphic.combining_len),
            scalar_storage.inline_scalars - 1,
        );
        var prepared: ?scalar_storage.Prepared = null;
        if (graphic.combining_len > direct) {
            var tail: [scalar_storage.maximum_tail_scalars]u32 = undefined;
            for (
                graphic.combining[direct..graphic.combining_len],
                0..,
            ) |scalar, index| tail[index] = scalar;
            prepared = self.scalars.?.prepare(
                tail[0 .. graphic.combining_len - direct],
            ) catch return false;
        }
        defer if (prepared) |*range| range.deinit();

        const right = self.rightBoundary();
        if (self.wrap_pending) {
            self.wrap_pending = false;
            if (self.cursor.col == right) {
                self.setRowWrapped(self.cursor.row, true);
                self.lineFeed();
                self.cursor.setColByClient(
                    if (self.left_right_margin_mode) self.left_margin else 0,
                );
            }
        }
        if (self.cells) |cells| {
            const target = cells[self.rowStart(self.cursor.row) + self.cursor.col];
            if (target.y > 0 and target.width > 0 and target.x < target.width) {
                const after = self.cursor.col -| target.x + target.width;
                if (after <= right) {
                    self.cursor.setColByClient(after);
                } else {
                    self.lineFeed();
                    self.cursor.setColByClient(
                        if (self.left_right_margin_mode) self.left_margin else 0,
                    );
                }
            }
        }
        if (graphic.width == 2 and self.cursor.col == right) {
            if (self.auto_wrap) {
                self.setRowWrapped(self.cursor.row, true);
                self.lineFeed();
                self.cursor.setColByClient(
                    if (self.left_right_margin_mode) self.left_margin else 0,
                );
            } else if (self.cursor.col > self.leftBoundary()) {
                self.cursor.setColByClient(self.cursor.col - 1);
            }
        }
        if (self.insert_mode) {
            const inserted = self.insertChars(graphic.width);
            std.debug.assert(inserted or !self.wrap_pending);
        }

        const cells = self.cells orelse unreachable;
        const index = self.rowStart(self.cursor.row) + self.cursor.col;
        var offset: u8 = 0;
        while (offset < graphic.width) : (offset += 1) {
            const col = self.cursor.col + offset;
            const target = cells[index + offset];
            if (target.width != 1 or target.height != 1 or
                target.x != 0 or target.y != 0)
            {
                std.debug.assert(self.clearClusterAt(
                    self.cursor.row,
                    col,
                    col != self.clusterAnchorCol(self.cursor.row, col),
                ));
            } else if (target.combining_len != 0) {
                clearAcceptedTail(
                    &self.scalars.?,
                    @intCast(index + offset),
                    target.combining_len,
                );
            }
        }
        var replay = Cell{
            .codepoint = graphic.codepoint,
            .width = graphic.width,
            .semantic_width = graphic.width == 2,
            .combining_len = graphic.combining_len,
            .attrs = self.current_attrs,
        };
        for (graphic.combining[0..direct], 0..) |scalar, scalar_index|
            replay.combining[scalar_index] = scalar;
        cells[index] = replay;
        if (prepared) |*range| {
            range.commit(index, 0) catch unreachable;
        }
        if (graphic.width == 2) {
            cells[index + 1] = .{
                .codepoint = 0,
                .width = 2,
                .x = 1,
                .semantic_width = graphic.width == 2,
                .attrs = self.current_attrs,
            };
        }
        self.last_graphic = graphic;
        const after = self.cursor.col + graphic.width;
        if (after <= right) {
            self.cursor.setColByClient(after);
        } else if (self.auto_wrap) {
            self.cursor.setColByClient(right);
            self.wrap_pending = true;
        } else {
            self.cursor.setColByClient(right);
        }
        return true;
    }

    /// Applies one validated OSC 66 sized-text payload.
    pub fn writeSizedText(self: *Screen, payload: []const u8) bool {
        const parsed = sized_text.parse(payload) orelse return false;
        var changed = false;
        var iterator = std.unicode.Utf8View.initUnchecked(parsed.text).iterator();
        if (parsed.width != 0) {
            var scalars: [scalar_storage.maximum_scalars]u21 = undefined;
            var count: u8 = 0;
            while (iterator.nextCodepoint()) |cp| {
                if (sized_text.isIgnoredCodepoint(cp)) continue;
                scalars[count] = @intCast(cp);
                count += 1;
            }
            if (count != 0) changed = self.writeSizedCluster(parsed, scalars[0..count], parsed.width);
            return changed;
        }

        var scalars: [scalar_storage.maximum_scalars]u21 = undefined;
        var count: u8 = 0;
        while (iterator.nextCodepoint()) |cp| {
            if (sized_text.isIgnoredCodepoint(cp)) continue;
            if (count != 0 and !sized_text.isTrailingCombiningCodepoint(cp)) {
                changed = self.writeSizedCluster(parsed, scalars[0..count], 1) or changed;
                count = 0;
            }
            scalars[count] = @intCast(cp);
            count += 1;
        }
        if (count != 0) changed = self.writeSizedCluster(parsed, scalars[0..count], 1) or changed;
        return changed;
    }

    fn writeSizedCluster(
        self: *Screen,
        parsed: sized_text.Value,
        scalars: []const u21,
        width_cells: u8,
    ) bool {
        std.debug.assert(scalars.len > 0 and
            scalars.len <= scalar_storage.maximum_scalars);
        const physical_width = @as(u16, parsed.scale) * width_cells;
        const height: u16 = parsed.scale;
        const left = self.leftBoundary();
        const right = self.rightBoundary();
        const available_width = right - left + 1;
        const available_height = self.scrollBottom() - self.scroll_top + 1;
        if (physical_width > available_width or height > available_height) return false;
        var prepared_tail: ?scalar_storage.Prepared = null;
        if (scalars.len > 1 + @as(usize, 3)) {
            var tail: [scalar_storage.maximum_tail_scalars]u32 = undefined;
            for (scalars[4..], 0..) |cp, index| tail[index] = cp;
            prepared_tail = self.scalars.?.prepare(tail[0 .. scalars.len - 4]) catch
                return false;
        }
        defer if (prepared_tail) |*prepared| prepared.deinit();

        var changed = self.cancelPendingWrap();
        if (self.cursor.col + physical_width - 1 > right) {
            if (self.auto_wrap) {
                self.setRowWrapped(self.cursor.row, true);
                self.lineFeed();
                self.cursor.setColByClient(left);
                changed = true;
            } else {
                self.cursor.setColByClient(right - physical_width + 1);
                changed = true;
            }
        }
        const bottom = self.scrollBottom();
        if (self.cursor.row + height - 1 > bottom) {
            const amount = self.cursor.row + height - 1 - bottom;
            changed = self.scrollUpRegion(self.scroll_top, bottom, amount) or changed;
            self.cursor.setPositionByClient(self.cursor.row - amount, self.cursor.col);
        }

        const cells = self.cells orelse return changed;
        const top = self.cursor.row;
        const start_col = self.cursor.col;
        const lead_index = self.rowStart(top) + start_col;
        const old_lead = cells[lead_index];
        const candidate_tail = if (scalars.len > scalar_storage.inline_scalars)
            scalars[scalar_storage.inline_scalars..]
        else
            &.{};
        const old_tail = acceptedTail(
            &self.scalars.?,
            lead_index,
            old_lead.combining_len,
        );
        var tail_changed = old_tail.len != candidate_tail.len;
        if (!tail_changed) {
            for (old_tail, candidate_tail) |old_scalar, candidate_scalar| {
                if (old_scalar != candidate_scalar) {
                    tail_changed = true;
                    break;
                }
            }
        }
        var row = top;
        while (row < top + height) : (row += 1) {
            var col = start_col;
            while (col < start_col + physical_width) : (col += 1)
                changed = self.clearClusterAt(row, col, false) or changed;
        }

        var cell = Cell{
            .codepoint = 0,
            .combining_len = 0,
            .width = @intCast(physical_width),
            .height = parsed.scale,
            .subscale_n = parsed.subscale_n,
            .subscale_d = parsed.subscale_d,
            .vertical_align = parsed.vertical_align,
            .horizontal_align = parsed.horizontal_align,
            .attrs = self.current_attrs,
        };
        row = top;
        while (row < top + height) : (row += 1) {
            cell.y = @intCast(row - top);
            var col = start_col;
            while (col < start_col + physical_width) : (col += 1) {
                cell.x = @intCast(col - start_col);
                const index = self.rowStart(row) + col;
                if (row == top and col == start_col) {
                    cell.codepoint = scalars[0];
                    cell.combining_len = @intCast(scalars.len - 1);
                    const direct = @min(scalars.len - 1, cell.combining.len);
                    for (scalars[1..][0..direct], 0..) |cp, scalar_index|
                        cell.combining[scalar_index] = cp;
                    if (prepared_tail) |*prepared| prepared.commit(
                        index,
                        cells[index].combining_len,
                    ) catch unreachable else clearAcceptedTail(
                        &self.scalars.?,
                        index,
                        cells[index].combining_len,
                    );
                } else {
                    clearAcceptedTail(
                        &self.scalars.?,
                        index,
                        cells[index].combining_len,
                    );
                    cell.codepoint = 0;
                    cell.combining_len = 0;
                    @memset(&cell.combining, 0);
                }
                if (!std.meta.eql(cells[@intCast(index)], cell)) {
                    cells[@intCast(index)] = cell;
                    changed = true;
                }
            }
        }
        changed = tail_changed or changed;
        self.last_graphic = null;
        if (start_col + physical_width <= right) {
            self.cursor.setColByClient(start_col + physical_width);
        } else if (self.auto_wrap) {
            self.cursor.setColByClient(right);
            self.wrap_pending = true;
        } else {
            self.cursor.setColByClient(right);
        }
        return changed;
    }

    /// Write one codepoint with Unicode occupancy, insertion, wrapping, dirty, and cursor semantics.
    fn writeCell(self: *Screen, cp: u21) void {
        if (!self.writeCellDisposition(cp)) return;
    }

    fn writeCellDisposition(self: *Screen, cp: u21) bool {
        if (self.cols == 0 or self.rows == 0) return false;
        const properties = unicode.properties(cp);
        if (properties.isInvalid()) return false;
        if (self.appendGraphemeToLeadCell(cp, properties)) |changed|
            return changed;
        if (properties.width() == 0) return false;

        const right = self.rightBoundary();
        const width: u8 = if (properties.width() == 2) 2 else 1;
        if (width > right - self.leftBoundary() + 1) return false;
        if (self.wrap_pending) {
            self.wrap_pending = false;
            if (self.cursor.col == right) {
                self.setRowWrapped(self.cursor.row, true);
                self.lineFeed();
                self.cursor.setColByClient(if (self.left_right_margin_mode) self.left_margin else 0);
            }
        }
        if (self.cells) |cells| {
            const target = cells[@intCast(self.rowStart(self.cursor.row) + self.cursor.col)];
            if (target.y > 0 and target.width > 0 and target.x < target.width) {
                const after = self.cursor.col -| target.x + target.width;
                if (after <= right) {
                    self.cursor.setColByClient(after);
                } else {
                    self.lineFeed();
                    self.cursor.setColByClient(if (self.left_right_margin_mode) self.left_margin else 0);
                }
            }
        }
        if (width == 2 and self.cursor.col == right) {
            if (self.auto_wrap) {
                self.setRowWrapped(self.cursor.row, true);
                self.lineFeed();
                self.cursor.setColByClient(
                    if (self.left_right_margin_mode) self.left_margin else 0,
                );
            } else if (self.cursor.col > self.leftBoundary()) {
                self.cursor.setColByClient(self.cursor.col - 1);
            }
        }
        if (self.insert_mode) {
            const inserted = self.insertChars(width);
            std.debug.assert(inserted or !self.wrap_pending);
        }
        if (self.cells) |cells| {
            const start = self.rowStart(self.cursor.row);
            var offset: u8 = 0;
            while (offset < width) : (offset += 1) {
                const col = self.cursor.col + offset;
                const target = cells[@intCast(start + @as(u32, col))];
                if (target.width != 1 or target.height != 1 or
                    target.x != 0 or target.y != 0)
                {
                    std.debug.assert(self.clearClusterAt(
                        self.cursor.row,
                        col,
                        col != self.clusterAnchorCol(self.cursor.row, col),
                    ));
                } else if (target.combining_len != 0) {
                    clearAcceptedTail(
                        &self.scalars.?,
                        start + @as(u32, col),
                        target.combining_len,
                    );
                }
            }
            const index = start + @as(u32, self.cursor.col);
            cells[@intCast(index)] = .{
                .codepoint = cp,
                .width = width,
                .semantic_width = width == 2,
                .attrs = self.current_attrs,
            };
            if (width == 2) {
                cells[@intCast(index + 1)] = .{
                    .codepoint = 0,
                    .width = 2,
                    .x = 1,
                    .semantic_width = true,
                    .attrs = self.current_attrs,
                };
            }
        }
        self.last_graphic = .{ .codepoint = cp, .width = width };
        const after = self.cursor.col + width;
        if (after <= right) {
            self.cursor.setColByClient(after);
        } else if (self.auto_wrap) {
            self.cursor.setColByClient(right);
            self.wrap_pending = true;
        } else {
            self.cursor.setColByClient(right);
        }
        return true;
    }

    fn appendGraphemeToLeadCell(
        self: *Screen,
        cp: u21,
        properties: unicode.Properties,
    ) ?bool {
        const pos = self.previousLeadCellPos() orelse return null;
        const cells = self.cells orelse return null;
        const observed = cells[@intCast(self.rowStart(pos.row) + pos.col)];
        const anchor_row = pos.row -| observed.y;
        const anchor_col = pos.col -| observed.x;
        const idx = self.rowStart(anchor_row) + @as(u32, anchor_col);
        const lead_cell = &cells[@intCast(idx)];
        if (lead_cell.codepoint == 0) return null;

        var state = unicode.GraphemeState{};
        var scalars: [scalar_storage.maximum_scalars]u32 = undefined;
        const accepted = self.cellScalarsAt(anchor_row, anchor_col, &scalars);
        for (accepted) |scalar|
            state = state.step(unicode.properties(@intCast(scalar)));
        const next = state.step(properties);
        if (!next.joinsCurrent()) return null;
        if (lead_cell.combining_len + 1 >= scalar_storage.maximum_scalars)
            return false;
        const changes_presentation = accepted.len != 0 and
            unicode.properties(@intCast(accepted[accepted.len - 1]))
                .isEmojiPresentationBase();
        if (cp == 0xfe0f and lead_cell.width == 1 and changes_presentation and
            self.rightBoundary() - self.leftBoundary() + 1 < 2)
        {
            return false;
        }

        const combining_index = lead_cell.combining_len;
        if (combining_index < lead_cell.combining.len) {
            lead_cell.combining[combining_index] = cp;
        } else {
            var candidate: [scalar_storage.maximum_tail_scalars]u32 = undefined;
            const old = acceptedTail(
                &self.scalars.?,
                idx,
                lead_cell.combining_len,
            );
            @memcpy(candidate[0..old.len], old);
            candidate[old.len] = cp;
            self.scalars.?.set(
                idx,
                lead_cell.combining_len,
                candidate[0 .. old.len + 1],
            ) catch
                return false;
        }
        lead_cell.combining_len = combining_index + 1;
        var final_width = lead_cell.width;
        if (cp == 0xfe0f and lead_cell.width == 1 and changes_presentation) {
            self.widenPresentation(anchor_row, anchor_col);
            final_width = 2;
        } else if (cp == 0xfe0e and lead_cell.width == 2 and changes_presentation) {
            self.narrowPresentation(anchor_row, anchor_col);
            final_width = 1;
        }
        if (self.last_graphic) |*graphic| {
            if (graphic.combining_len < graphic.combining.len) {
                graphic.combining[graphic.combining_len] = cp;
                graphic.combining_len += 1;
                graphic.width = final_width;
            }
        }
        return true;
    }

    fn widenPresentation(self: *Screen, row: u16, col: u16) void {
        const right = self.rightBoundary();
        const cells = self.cells orelse return;
        if (col == right) {
            const lead_index = self.rowStart(row) + col;
            const lead = cells[@intCast(lead_index)];
            const destination_col: u16 = if (self.auto_wrap)
                if (self.left_right_margin_mode) self.left_margin else 0
            else
                col - 1;
            if (!self.auto_wrap) {
                const destination = self.rowStart(row) + destination_col;
                const destination_cleared =
                    self.clearReplacementOwnershipAt(row, destination_col);
                std.debug.assert(destination_cleared or
                    cells[@intCast(destination)].combining_len == 0);
                self.scalars.?.move(
                    lead_index,
                    lead.combining_len,
                    destination,
                    cells[@intCast(destination)].combining_len,
                ) catch @panic("accepted presentation relocation scalar mismatch");
                var moved = lead;
                moved.width = 2;
                moved.semantic_width = true;
                cells[@intCast(destination)] = moved;
                cells[@intCast(lead_index)] = .{
                    .codepoint = 0,
                    .width = 2,
                    .x = 1,
                    .semantic_width = true,
                    .attrs = moved.attrs,
                };
                self.wrap_pending = false;
                self.cursor.setColByClient(right);
                return;
            }

            var cluster: [scalar_storage.maximum_scalars]u32 = undefined;
            const accepted = self.cellScalarsAt(row, col, &cluster);
            clearAcceptedTail(&self.scalars.?, lead_index, lead.combining_len);
            cells[@intCast(lead_index)] = blank_cell;
            self.setRowWrapped(row, true);
            self.lineFeed();
            self.cursor.setColByClient(destination_col);
            const destination = self.rowStart(self.cursor.row) + destination_col;
            const continuation = destination + 1;
            const destination_cleared = self.clearReplacementOwnershipAt(
                self.cursor.row,
                destination_col,
            );
            std.debug.assert(destination_cleared or
                cells[@intCast(destination)].combining_len == 0);
            const continuation_cleared = self.clearReplacementOwnershipAt(
                self.cursor.row,
                destination_col + 1,
            );
            std.debug.assert(continuation_cleared or
                cells[@intCast(continuation)].combining_len == 0);
            var moved = lead;
            moved.width = 2;
            moved.semantic_width = true;
            cells[@intCast(destination)] = moved;
            if (accepted.len > scalar_storage.inline_scalars) {
                self.scalars.?.set(
                    destination,
                    0,
                    accepted[scalar_storage.inline_scalars..],
                ) catch @panic("accepted presentation relocation lost capacity");
            }
            cells[@intCast(continuation)] = .{
                .codepoint = 0,
                .width = 2,
                .x = 1,
                .semantic_width = true,
                .attrs = moved.attrs,
            };
            const after = destination_col + 2;
            if (after <= right) {
                self.cursor.setColByClient(after);
            } else {
                self.cursor.setColByClient(right);
                self.wrap_pending = true;
            }
            return;
        }
        const next_col = col + 1;
        const next_index = self.rowStart(row) + next_col;
        const next = cells[@intCast(next_index)];
        if (next.codepoint != 0 or next.width != 1 or next.height != 1 or
            next.x != 0 or next.y != 0)
        {
            std.debug.assert(self.clearClusterAt(
                row,
                next_col,
                next_col != self.clusterAnchorCol(row, next_col),
            ));
        }
        const lead_index = self.rowStart(row) + col;
        cells[@intCast(lead_index)].width = 2;
        cells[@intCast(lead_index)].semantic_width = true;
        cells[@intCast(next_index)] = .{
            .codepoint = 0,
            .width = 2,
            .x = 1,
            .semantic_width = true,
            .attrs = cells[@intCast(lead_index)].attrs,
        };
        if (self.cursor.row == row and !self.wrap_pending and
            self.cursor.col == next_col)
        {
            if (next_col < right) {
                self.cursor.setColByClient(next_col + 1);
            } else {
                self.cursor.setColByClient(right);
                if (self.auto_wrap) self.wrap_pending = true;
            }
        }
    }

    fn narrowPresentation(self: *Screen, row: u16, col: u16) void {
        const cells = self.cells orelse return;
        const lead_index = self.rowStart(row) + col;
        cells[@intCast(lead_index)].width = 1;
        cells[@intCast(lead_index)].semantic_width = false;
        if (col + 1 < self.cols) {
            const continuation_index = lead_index + 1;
            cells[@intCast(continuation_index)] = blank_cell;
        }
        if (self.cursor.row == row) {
            if (self.wrap_pending) {
                self.wrap_pending = false;
                self.cursor.setColByClient(col + 1);
            } else if (self.cursor.col > col + 1) {
                self.cursor.setColByClient(self.cursor.col - 1);
            }
        }
    }

    fn previousLeadCellPos(self: *const Screen) ?struct { row: u16, col: u16 } {
        const right = self.rightBoundary();
        if (self.wrap_pending) return .{ .row = self.cursor.row, .col = right };
        if (!self.auto_wrap and self.cursor.col == right) {
            const cells = self.cells orelse return null;
            const current = cells[@intCast(self.rowStart(self.cursor.row) + right)];
            if (self.last_graphic) |graphic| {
                if (current.codepoint == graphic.codepoint and
                    current.width == graphic.width and current.x == 0)
                    return .{ .row = self.cursor.row, .col = right };
            }
        }

        if (self.cursor.col == 0) return null;
        return .{ .row = self.cursor.row, .col = self.cursor.col - 1 };
    }

    // -------------------------------------------------------------------------
    // Rendition
    // -------------------------------------------------------------------------

    /// Apply SGR parameters to the retained attributes used by subsequent writes.
    pub fn applySgr(self: *Screen, operands: SgrOperands) bool {
        const params = operands.values;
        const before = self.current_attrs;
        if (params.len == 0) {
            self.resetRendition();
            return !std.meta.eql(before, self.current_attrs);
        }

        std.debug.assert(params.len <= SgrOperands.capacity);
        const param_len: u8 = @intCast(params.len);
        var idx: u8 = 0;
        while (idx < param_len) : (idx += 1) {
            const param = params[idxOf(idx)];
            switch (param) {
                4 => self.applyUnderlineStyle(operands, &idx),
                38 => self.applyExtendedColor(operands, &idx, true),
                48 => self.applyExtendedColor(operands, &idx, false),
                58 => self.applyUnderlineColor(operands, &idx),
                else => self.applyBasicSgr(param),
            }
        }
        return !std.meta.eql(before, self.current_attrs);
    }

    // SGR does not own ISO or DEC character protection.
    fn resetRendition(self: *Screen) void {
        const protection = self.current_attrs.protected;
        self.current_attrs = initial_cell_attrs;
        self.current_attrs.protected = protection;
    }

    fn applyBasicSgr(self: *Screen, param: i32) void {
        switch (param) {
            0 => self.resetRendition(),
            1 => self.current_attrs.bold = true,
            2 => self.current_attrs.dim = true,
            3 => self.current_attrs.italic = true,
            5 => self.current_attrs.blink = true,
            7 => self.current_attrs.reverse = true,
            8 => self.current_attrs.invisible = true,
            9 => self.current_attrs.strikethrough = true,
            10...19 => self.current_attrs.font = @intCast(param - 10),
            21 => self.setUnderline(.double),
            22 => {
                self.current_attrs.bold = false;
                self.current_attrs.dim = false;
            },
            23 => self.current_attrs.italic = false,
            24 => self.clearUnderline(),
            25 => self.clearBlink(),
            27 => self.current_attrs.reverse = false,
            28 => self.current_attrs.invisible = false,
            29 => self.current_attrs.strikethrough = false,
            30...37 => self.current_attrs.fg = screenAnsi16Color(@intCast(param - 30)),
            39 => self.current_attrs.fg = initial_cell_attrs.fg,
            40...47 => self.current_attrs.bg = screenAnsi16Color(@intCast(param - 40)),
            49 => self.current_attrs.bg = initial_cell_attrs.bg,
            59 => self.current_attrs.underline_color = default_cell_underline_color,
            73 => self.current_attrs.baseline = .raised,
            74 => self.current_attrs.baseline = .lowered,
            75 => self.current_attrs.baseline = .normal,
            90...97 => self.current_attrs.fg = screenAnsi16Color(@intCast((param - 90) + 8)),
            100...107 => self.current_attrs.bg = screenAnsi16Color(@intCast((param - 100) + 8)),
            else => {},
        }
    }

    fn applyUnderlineStyle(self: *Screen, operands: SgrOperands, idx: *u8) void {
        const params = operands.values;
        const next = idx.* + 1;
        if (next < params.len and operands.colonAfter(idx.*)) {
            self.setUnderlineStyle(params[idxOf(next)]);
            idx.* += 1;
            return;
        }
        self.current_attrs.underline = true;
        self.current_attrs.underline_style = .straight;
    }

    fn setUnderlineStyle(self: *Screen, value: i32) void {
        switch (value) {
            0 => self.clearUnderline(),
            1 => self.setUnderline(.straight),
            2 => self.setUnderline(.double),
            3 => self.setUnderline(.curly),
            4 => self.setUnderline(.dotted),
            5 => self.setUnderline(.dashed),
            else => {},
        }
    }

    fn setUnderline(self: *Screen, underline_style: UnderlineStyle) void {
        self.current_attrs.underline = true;
        self.current_attrs.underline_style = underline_style;
    }

    fn clearUnderline(self: *Screen) void {
        self.current_attrs.underline = false;
        self.current_attrs.underline_style = .straight;
    }

    fn clearBlink(self: *Screen) void {
        self.current_attrs.blink = false;
        self.current_attrs.blink_fast = false;
    }

    fn applyExtendedColor(
        self: *Screen,
        operands: SgrOperands,
        idx: *u8,
        is_fg: bool,
    ) void {
        const sgr_color = decodeExtendedColor(operands, idx) orelse return;
        if (is_fg) self.current_attrs.fg = sgr_color else self.current_attrs.bg = sgr_color;
    }

    fn applyUnderlineColor(
        self: *Screen,
        operands: SgrOperands,
        idx: *u8,
    ) void {
        const sgr_color = decodeExtendedColor(operands, idx) orelse return;
        self.current_attrs.underline_color = sgr_color;
    }

    // -------------------------------------------------------------------------
    // Tabs, scrolling, margins, and history restoration
    // -------------------------------------------------------------------------

    /// Move forward through at most `count` tab stops, clamping at the last column.
    fn horizontalTabForward(self: *Screen, count: u16) void {
        if (self.cols == 0) return;
        const line_cols = self.lineColumnCount(self.cursor.row);
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (self.cursor.col >= line_cols - 1) break;
            var col = self.cursor.col + 1;
            while (col < line_cols and !self.tabStopAt(col)) : (col += 1) {}
            self.cursor.setColByClient(if (col < line_cols) col else line_cols - 1);
        }
    }

    /// Move backward through at most `count` tab stops, clamping at column zero.
    fn horizontalTabBack(self: *Screen, count: u16) void {
        var remaining = count;
        while (remaining > 0) : (remaining -= 1) {
            if (self.cursor.col == 0) break;
            var col = self.cursor.col - 1;
            while (col > 0 and !self.tabStopAt(col)) : (col -= 1) {}
            self.cursor.setColByClient(if (self.tabStopAt(col)) col else 0);
        }
    }

    /// Advance within the scroll region, scrolling it upward at its bottom edge.
    /// Applies one terminal line feed within the active vertical margins.
    pub fn lineFeed(self: *Screen) void {
        if (self.rows == 0) return;
        const bottom = self.scrollBottom();
        if (self.cursor.row < bottom) {
            self.setCursorRowClamped(self.cursor.row + 1);
            return;
        }
        if (self.cursor.row == bottom) {
            std.debug.assert(self.scrollUpRegion(self.scroll_top, bottom, 1));
            return;
        }
        if (self.cursor.row < self.rows - 1) self.setCursorRowClamped(self.cursor.row + 1);
    }

    /// Move upward, scrolling the active region downward at its top edge.
    pub fn reverseIndex(self: *Screen) bool {
        const changed = self.cancelPendingWrap();
        if (self.rows == 0) return changed;
        if (self.cursor.row == self.scroll_top) {
            return self.scrollDownRegion(self.scroll_top, self.scrollBottom(), 1) or changed;
        }
        const row = self.cursor.row;
        self.setCursorRowClamped(row -| 1);
        return self.cursor.row != row or changed;
    }

    /// Applies DECFI within the cursor's horizontal region.
    pub fn forwardIndex(self: *Screen) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0) return changed;
        const inside = self.cursorWithinHorizontalMargins();
        const right = if (inside and self.left_right_margin_mode) self.right_margin else self.cols - 1;
        if (self.cursor.col < right) {
            self.cursor.setColByClient(self.cursor.col + 1);
            return true;
        }
        if (self.cursor.col == right) {
            changed = self.shiftColumnsLeftInBounds(1, if (inside) self.leftBoundary() else 0, right) or changed;
        }
        return changed;
    }

    /// Applies DECBI within the cursor's horizontal region.
    pub fn backIndex(self: *Screen) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0) return changed;
        const inside = self.cursorWithinHorizontalMargins();
        const left = if (inside and self.left_right_margin_mode) self.left_margin else 0;
        if (self.cursor.col > left) {
            self.cursor.setColByClient(self.cursor.col - 1);
            return true;
        }
        if (self.cursor.col == left) {
            const right = if (inside and self.left_right_margin_mode) self.right_margin else self.cols - 1;
            changed = self.shiftColumnsRightInBounds(1, left, right) or changed;
        }
        return changed;
    }

    fn scrollUp(self: *Screen) void {
        const cells = self.cells orelse return;
        if (self.rows == 0 or self.cols == 0) return;
        if (self.clearNonSemanticClustersIntersecting(0, 1, 0, self.cols)) {
            self.setRowWrapped(0, false);
        }
        const row_len = @as(u32, self.cols);
        self.storeHistoryRow(0);
        self.row_origin = (self.row_origin + 1) % self.rows;
        const bottom_start = self.rowStart(self.rows - 1);
        self.clearScalarCells(bottom_start, row_len);
        @memset(cells[@intCast(bottom_start)..@intCast(bottom_start + row_len)], blank_cell);
        self.setRowWrapped(self.rows - 1, false);
        self.resetLineGeometry(self.rows - 1);
    }

    /// Returns the effective lower vertical margin.
    pub fn scrollBottom(self: *const Screen) u16 {
        return if (self.rows == 0) 0 else @min(self.scroll_bottom, self.rows - 1);
    }

    /// Set zero-based vertical margins after clamping them to the grid.
    ///
    /// An unordered result changes nothing. A valid command homes the cursor,
    /// cancels pending wrap, and reports whether any retained state changed.
    pub fn setScrollRegion(self: *Screen, top: u16, bottom: ?u16) bool {
        if (self.rows == 0) {
            const changed = self.scroll_top != 0 or self.scroll_bottom != 0 or
                self.cursor.row != 0 or self.cursor.col != 0 or self.wrap_pending;
            self.scroll_top = 0;
            self.scroll_bottom = 0;
            self.cursor.setPositionByClient(0, 0);
            self.wrap_pending = false;
            return changed;
        }

        const new_top = @min(top, self.rows - 1);
        const new_bottom = if (bottom) |value| @min(value, self.rows - 1) else self.rows - 1;
        if (new_top >= new_bottom) return false;

        const home_row = if (self.origin_mode) new_top else 0;
        const home_col = self.lineHomeCol();
        const changed = self.scroll_top != new_top or self.scroll_bottom != new_bottom or
            self.cursor.row != home_row or self.cursor.col != home_col or self.wrap_pending;
        self.scroll_top = new_top;
        self.scroll_bottom = new_bottom;
        self.cursor.setPositionByClient(home_row, home_col);
        self.wrap_pending = false;
        return changed;
    }

    /// Enable horizontal margins, or disable them and restore full-width defaults.
    ///
    /// Every enable clears physical-row geometry, including repeated sets after
    /// a screen-bank switch. The result reports every resulting state mutation.
    /// Selects DEC left/right margin mode and restores full-width margins.
    pub fn setLeftRightMarginMode(self: *Screen, enabled: bool) bool {
        var changed = self.left_right_margin_mode != enabled;
        self.left_right_margin_mode = enabled;
        if (enabled) {
            var row: u16 = 0;
            while (row < self.rows) : (row += 1) {
                if (self.lineGeometry(row) == .single_width) continue;
                self.resetLineGeometry(row);
                changed = true;
            }
        }
        if (!enabled) {
            changed = changed or self.left_margin != 0 or self.right_margin != self.cols -| 1;
            self.left_margin = 0;
            self.right_margin = self.cols -| 1;
        }
        return changed;
    }

    /// Set zero-based horizontal margins while left-right margin mode is active.
    ///
    /// Disabled, undersized, or unordered input changes nothing. A valid command
    /// homes the cursor, cancels pending wrap, and reports exact retained mutation.
    pub fn setLeftRightMargins(self: *Screen, left: u16, right: ?u16) bool {
        if (!self.left_right_margin_mode or self.cols < 2) return false;
        if (left >= self.cols - 1) return false;
        if (right) |value| if (left >= value) return false;
        const new_left = @min(left, self.cols - 2);
        const new_right = if (right) |value| @min(value, self.cols - 1) else self.cols - 1;
        if (new_left >= new_right) return false;
        const home_row = if (self.origin_mode) self.scroll_top else 0;
        const home_col = if (self.origin_mode) new_left else 0;
        const changed = self.left_margin != new_left or self.right_margin != new_right or
            self.cursor.row != home_row or self.cursor.col != home_col or self.wrap_pending;
        self.left_margin = new_left;
        self.right_margin = new_right;
        self.wrap_pending = false;
        self.cursor.setPositionByClient(home_row, home_col);
        return changed;
    }

    /// Insert at least one line at an admitted cursor inside both active regions.
    ///
    /// Counts clamp to the remaining region. An outside cursor changes only a
    /// pending-wrap state; the result reports exact row or wrap mutation.
    pub fn insertLines(self: *Screen, count: u16) bool {
        const changed = self.cancelPendingWrap();
        const bottom = self.scrollBottom();
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;
        return self.scrollDownRegion(self.cursor.row, bottom, @max(count, 1)) or changed;
    }

    /// Delete at least one line at an admitted cursor inside both active regions.
    ///
    /// Counts clamp to the remaining region. An outside cursor changes only a
    /// pending-wrap state; the result reports exact row or wrap mutation.
    pub fn deleteLines(self: *Screen, count: u16) bool {
        const changed = self.cancelPendingWrap();
        const bottom = self.scrollBottom();
        if (self.cursor.row < self.scroll_top or self.cursor.row > bottom) return changed;
        if (!self.cursorWithinHorizontalMargins()) return changed;
        return self.scrollUpRegion(self.cursor.row, bottom, @max(count, 1)) or changed;
    }

    fn cursorWithinHorizontalMargins(self: *const Screen) bool {
        if (!self.left_right_margin_mode) return true;
        return self.cursor.col >= self.left_margin and self.cursor.col <= self.right_margin;
    }

    /// Scroll an ordered region upward by at most its bounded row count.
    /// Returns exact cell, row, history, damage, or pending-wrap mutation.
    pub fn scrollUpRegion(self: *Screen, top: u16, bottom: u16, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0 or top >= self.rows or top > bottom) return changed;
        const bounded_bottom = @min(bottom, self.rows - 1);
        const region_len: u16 = bounded_bottom - top + 1;
        const amount = @min(count, region_len);
        if (amount == 0) return changed;
        changed = self.clearNonSemanticClustersIntersecting(
            top,
            top + amount,
            0,
            self.cols,
        ) or changed;
        changed = self.clearNonSemanticClustersIntersecting(
            bounded_bottom,
            bounded_bottom + 1,
            0,
            self.cols,
        ) or changed;

        if (top == 0 and bounded_bottom == self.rows - 1) {
            var remaining = amount;
            while (remaining > 0) : (remaining -= 1) self.scrollUp();
            return true;
        }

        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
        if (left != 0 or right + 1 != self.cols) {
            changed = self.clearClustersIntersecting(top, bounded_bottom + 1, left, right + 1) or changed;
        }

        var dst = top;
        while (dst + amount <= bounded_bottom) : (dst += 1) {
            changed = self.moveRowRange(dst, dst + amount, left, right + 1) or changed;
        }

        var clear_row = bounded_bottom - (amount - 1);
        while (clear_row <= bounded_bottom) : (clear_row += 1) {
            changed = self.clearClustersIntersecting(clear_row, clear_row + 1, left, right + 1) or changed;
            changed = self.clearStructuralRowRange(clear_row, left, right + 1) or changed;
        }
        return changed;
    }

    /// Scroll an ordered region downward by at most its bounded row count.
    /// Returns exact cell, row, damage, or pending-wrap mutation.
    pub fn scrollDownRegion(self: *Screen, top: u16, bottom: u16, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0 or top >= self.rows or top > bottom) return changed;
        const bounded_bottom = @min(bottom, self.rows - 1);
        const region_len: u16 = bounded_bottom - top + 1;
        const amount = @min(count, region_len);
        if (amount == 0) return changed;
        changed = self.clearClustersIntersecting(
            bounded_bottom - (amount - 1),
            bounded_bottom + 1,
            0,
            self.cols,
        ) or changed;
        changed = self.clearClustersIntersecting(top, top + 1, 0, self.cols) or changed;

        if (top == 0 and bounded_bottom == self.rows - 1 and !self.left_right_margin_mode) {
            self.row_origin = @intCast((@as(u32, self.row_origin) + @as(u32, self.rows) - @as(u32, amount)) % @as(u32, self.rows));
            var clear_row: u16 = 0;
            while (clear_row < amount) : (clear_row += 1) {
                changed = self.clearStructuralRowRange(clear_row, 0, self.cols) or changed;
            }
            return true;
        }

        const left = if (self.left_right_margin_mode) self.left_margin else 0;
        const right = if (self.left_right_margin_mode) self.right_margin else self.cols -| 1;
        if (left != 0 or right + 1 != self.cols) {
            changed = self.clearClustersIntersecting(top, bounded_bottom + 1, left, right + 1) or changed;
        }

        var dst = bounded_bottom;
        while (dst >= top + amount) {
            changed = self.moveRowRange(dst, dst - amount, left, right + 1) or changed;
            if (dst == top + amount) break;
            dst -= 1;
        }

        var clear_row = top;
        while (clear_row < top + amount) : (clear_row += 1) {
            changed = self.clearClustersIntersecting(clear_row, clear_row + 1, left, right + 1) or changed;
            changed = self.clearStructuralRowRange(clear_row, left, right + 1) or changed;
        }
        return changed;
    }

    // Removes the newest projected history row after its cells and scalar tails
    // have been restored into the visible grid. The oldest retained frontier and
    // its bounded output-only prefix are unchanged.
    fn consumeNewestHistoryRow(self: *Screen) void {
        std.debug.assert(self.history_count > 0);
        const projected_slot = self.historySlotForRecency(0) orelse
            @panic("accepted newest projected-history row missing");
        self.clearProjectedSlot(projected_slot);
        self.history_count -= 1;
        if (self.history_count == 0) self.history_write_idx = 0;
    }

    /// Reverse-scroll and restore newest primary scrollback rows when available.
    /// Restores up to `count` retained rows into the visible grid.
    pub fn scrollDownFromHistory(self: *Screen, count: u16) bool {
        var changed = self.cancelPendingWrap();
        if (self.rows == 0 or self.cols == 0 or count == 0) return changed;
        const limit = @max(@as(u32, self.rows), self.history_count);
        var remaining: u32 = @min(@as(u32, count), limit);
        while (remaining > 0) : (remaining -= 1) {
            const history_slot = self.historySlotForRecency(0);
            const history_flags = if (history_slot) |slot| self.history_flags.?[@intCast(slot)] else 0;
            if (history_slot) |slot| {
                if (!self.preflightHistoryRestore(slot)) break;
            }
            changed = self.scrollDownRegion(self.scroll_top, self.scrollBottom(), 1) or changed;
            if (history_slot) |slot| {
                const history = self.history.?;
                const source = slot * @as(u32, self.cols);
                const destination = self.rowStart(self.scroll_top);
                self.commitHistoryRestore(slot, destination);
                @memcpy(
                    self.cells.?[@intCast(destination)..@intCast(destination + self.cols)],
                    history[@intCast(source)..@intCast(source + self.cols)],
                );
                self.row_flags.?[@intCast(self.rowWrapIndex(self.scroll_top).?)] = history_flags;
                self.consumeNewestHistoryRow();
                changed = true;
            }
        }
        return changed;
    }

    fn preflightHistoryRestore(self: *Screen, slot: u32) bool {
        const history = self.history orelse return false;
        const history_scalars = if (self.history_scalars) |*storage|
            storage
        else
            return false;
        const visible = self.cells orelse return false;
        const visible_scalars = if (self.scalars) |*storage|
            storage
        else
            return false;
        const plans = self.history_plan orelse return false;
        const outgoing = self.history_plan_outgoing orelse return false;
        const incoming = self.history_plan_incoming orelse return false;
        if (plans.len != self.cols or outgoing.len != self.cols or
            incoming.len != self.cols)
            return false;
        const source = slot * @as(u32, self.cols);
        const released = self.rowStart(self.scrollBottom());
        if (source + self.cols > history.len or
            released + self.cols > visible.len)
            return false;
        @memset(plans, .none);
        var col: usize = 0;
        while (col < self.cols) : (col += 1) {
            outgoing[col] = visible[released + col].combining_len;
            incoming[col] = history[source + col].combining_len;
            if (!visible_scalars.validRange(released + col, outgoing[col]) or
                !history_scalars.validRange(source + col, incoming[col]))
                @panic("accepted history restore scalar mismatch");
            const count = @as(usize, incoming[col]) -|
                (scalar_storage.inline_scalars - 1);
            if (count == 0) continue;
            plans[col] = visible_scalars.planFirstFit(
                count,
                released,
                outgoing,
                plans[0..col],
                incoming[0..col],
            ) catch return false;
        }
        return true;
    }

    fn commitHistoryRestore(self: *Screen, slot: u32, destination: u32) void {
        const history_scalars = &self.history_scalars.?;
        const visible = self.cells.?;
        const visible_scalars = &self.scalars.?;
        const plans = self.history_plan.?;
        const incoming = self.history_plan_incoming.?;
        const source = slot * @as(u32, self.cols);
        var col: usize = 0;
        while (col < self.cols) : (col += 1) {
            const count = @as(usize, incoming[col]) -|
                (scalar_storage.inline_scalars - 1);
            if (count == 0) continue;
            const values = acceptedTail(
                history_scalars,
                source + col,
                incoming[col],
            );
            var prepared = visible_scalars.prepare(values) catch
                @panic("history restore preflight diverged");
            prepared.commitPlanned(
                plans[col],
                destination + col,
                visible[destination + col].combining_len,
            ) catch @panic("history restore first-fit plan diverged");
        }
    }

    // -------------------------------------------------------------------------
    // Row geometry and structural ownership
    // -------------------------------------------------------------------------

    fn rowStart(self: *const Screen, logical_row: u16) u32 {
        if (self.rows == 0) return 0;
        const physical_row = (self.row_origin + logical_row) % self.rows;
        return @as(u32, physical_row) * @as(u32, self.cols);
    }

    fn rowWrapIndex(self: *const Screen, logical_row: u16) ?u16 {
        if (self.row_flags == null) return null;
        if (self.rows == 0 or logical_row >= self.rows) return null;
        return (self.row_origin + logical_row) % self.rows;
    }

    /// Reports whether a visible row continues into the next row.
    pub fn rowWrapped(self: *const Screen, logical_row: u16) bool {
        const flags = self.row_flags orelse return false;
        const idx = self.rowWrapIndex(logical_row) orelse return false;
        return flags[@intCast(idx)] & row_wrapped_bit != 0;
    }

    /// Returns one visible row's DEC geometry, defaulting outside retained state.
    pub fn lineGeometry(self: *const Screen, logical_row: u16) LineGeometry {
        const flags = self.row_flags orelse return .single_width;
        const idx = self.rowWrapIndex(logical_row) orelse return .single_width;
        return @fromBackingInt(@intCast((flags[@intCast(idx)] & row_geometry_mask) >> row_geometry_shift));
    }

    fn setLineGeometry(self: *Screen, logical_row: u16, geometry: LineGeometry) bool {
        const flags = self.row_flags orelse return false;
        const idx = self.rowWrapIndex(logical_row) orelse return false;
        const previous = self.lineGeometry(logical_row);
        if (previous == geometry) return false;
        flags[@intCast(idx)] = (flags[@intCast(idx)] & ~row_geometry_mask) |
            (@as(u8, @backingInt(geometry)) << row_geometry_shift);
        const width = self.lineColumnCount(logical_row);
        if (self.cells != null and width < self.cols) self.clearRowRange(logical_row, width, self.cols);
        if (self.cursor.row == logical_row) {
            self.cursor.setColByClient(@min(self.cursor.col, width -| 1));
            self.wrap_pending = false;
        }
        return true;
    }

    /// Applies one DEC line-presentation geometry at the cursor row.
    pub fn applyLineGeometry(self: *Screen, geometry: LineGeometry) bool {
        if (self.left_right_margin_mode) return false;
        return self.setLineGeometry(self.cursor.row, geometry);
    }

    fn resetLineGeometry(self: *Screen, row: u16) void {
        if (self.lineGeometry(row) == .single_width) return;
        std.debug.assert(self.setLineGeometry(row, .single_width));
    }

    /// Applies the DEC screen-alignment fill and reports semantic change.
    pub fn alignmentDisplay(self: *Screen) bool {
        const cells = self.cells orelse return false;
        const fill = Cell{ .codepoint = 'E', .attrs = self.current_attrs };
        const erased = self.eraseCell();
        var changed = self.wrap_pending;
        self.wrap_pending = false;
        var row: u16 = 0;
        while (row < self.rows) : (row += 1) {
            const start = self.rowStart(row);
            const line_cols = self.lineColumnCount(row);
            var row_changed = false;
            for (
                cells[@intCast(start)..@intCast(start + line_cols)],
                0..,
            ) |*cell, col| {
                if (std.meta.eql(cell.*, fill)) continue;
                clearAcceptedTail(
                    &self.scalars.?,
                    start + @as(u32, @intCast(col)),
                    cell.combining_len,
                );
                cell.* = fill;
                row_changed = true;
            }
            for (
                cells[@intCast(start + line_cols)..@intCast(start + self.cols)],
                line_cols..,
            ) |*cell, col| {
                if (std.meta.eql(cell.*, erased)) continue;
                clearAcceptedTail(
                    &self.scalars.?,
                    start + @as(u32, @intCast(col)),
                    cell.combining_len,
                );
                cell.* = erased;
                row_changed = true;
            }
            if (self.row_flags) |flags| {
                const idx = self.rowWrapIndex(row) orelse unreachable;
                if (flags[@intCast(idx)] & row_wrapped_bit != 0) {
                    flags[@intCast(idx)] &= ~row_wrapped_bit;
                    row_changed = true;
                }
            }
            if (row_changed) {
                changed = true;
            }
        }
        return changed;
    }

    fn lineColumnCount(self: *const Screen, logical_row: u16) u16 {
        return switch (self.lineGeometry(logical_row)) {
            .single_width => self.cols,
            .double_width, .double_height_top, .double_height_bottom => @max(@as(u16, 1), self.cols / 2),
        };
    }

    fn setRowWrapped(self: *Screen, logical_row: u16, wrapped: bool) void {
        const flags = self.row_flags orelse return;
        const idx = self.rowWrapIndex(logical_row) orelse return;
        if (wrapped)
            flags[@intCast(idx)] |= row_wrapped_bit
        else
            flags[@intCast(idx)] &= ~row_wrapped_bit;
    }

    fn rowFlags(wrapped: bool, geometry: LineGeometry) u8 {
        return (if (wrapped) row_wrapped_bit else 0) |
            (@as(u8, @backingInt(geometry)) << row_geometry_shift);
    }

    fn columnCountForGeometry(self: *const Screen, geometry: LineGeometry) u16 {
        return switch (geometry) {
            .single_width => self.cols,
            .double_width, .double_height_top, .double_height_bottom => @max(@as(u16, 1), self.cols / 2),
        };
    }

    fn retainedRowCount(self: *const Screen) u32 {
        return std.math.add(u32, self.history_count, self.rows) catch
            @panic("retained terminal row count overflow");
    }

    fn retainedRowAt(self: *const Screen, logical_row: u32) RetainedRow {
        std.debug.assert(logical_row < self.retainedRowCount());
        if (logical_row < self.history_count) {
            const slot = self.historySlotForLogicalRow(logical_row) orelse unreachable;
            const base = slot * @as(u32, self.cols);
            const history = self.history orelse unreachable;
            const flags = self.history_flags orelse unreachable;
            const value = flags[@intCast(slot)];
            return .{
                .cells = history[@intCast(base)..@intCast(base + self.cols)],
                .scalars = &self.history_scalars.?,
                .scalar_start = base,
                .wrapped = value & row_wrapped_bit != 0,
                .geometry = @fromBackingInt(@intCast(
                    (value & row_geometry_mask) >> row_geometry_shift,
                )),
            };
        }

        const visible_row: u16 = @intCast(logical_row - self.history_count);
        return .{
            .cells = self.visibleRowCells(visible_row),
            .scalars = &self.scalars.?,
            .scalar_start = self.rowStart(visible_row),
            .wrapped = self.rowWrapped(visible_row),
            .geometry = self.lineGeometry(visible_row),
        };
    }

    fn retainedRowContentLen(self: *const Screen, row: RetainedRow) u16 {
        const line_cols = self.columnCountForGeometry(row.geometry);
        var col = line_cols;
        while (col > 0) {
            const index = col - 1;
            const cell = row.cells[index];
            if (cell.codepoint != 0) {
                if (isSemanticWideLead(cell)) {
                    return @min(line_cols, col + @as(u16, cell.width) - 1);
                }
                return col;
            }
            col -= 1;
        }
        if (row.wrapped and line_cols > 0) return line_cols;
        return 0;
    }

    fn currentRetainedLineRange(self: *const Screen) RetainedLineRange {
        const total = self.retainedRowCount();
        std.debug.assert(total > 0);
        var start = self.history_count + self.cursor.row;
        std.debug.assert(start < total);
        while (start > 0 and self.retainedRowAt(start - 1).wrapped) start -= 1;

        var end = start + 1;
        while (end < total and self.retainedRowAt(end - 1).wrapped) end += 1;
        return .{ .start = start, .end = end };
    }

    fn clearHistoryBoundary(self: *Screen) void {
        self.history_boundary_stored = 0;
        self.history_boundary_total = 0;
        self.history_boundary_active = false;
    }

    fn appendHistoryBoundaryRow(self: *Screen, row: RetainedRow) void {
        const storage = self.history_boundary_text orelse unreachable;
        if (!self.history_boundary_active) {
            self.history_boundary_stored = 0;
            self.history_boundary_total = 0;
            self.history_boundary_active = true;
        }
        var writer = HistoryBoundaryWriter{
            .storage = storage,
            .stored = self.history_boundary_stored,
            .total = self.history_boundary_total,
        };
        const text_writer = RetainedTextWriter{ .history_boundary = &writer };
        const content_len = self.retainedRowContentLen(row);
        var col: u16 = 0;
        while (col < content_len) : (col += 1) {
            const cell = row.cells[col];
            writeCellText(
                text_writer,
                cell,
                externalCellScalars(row.scalars, row.scalar_start + col, cell),
            );
        }
        self.history_boundary_stored = writer.stored;
        self.history_boundary_total = writer.total;
    }

    fn recordDroppedProjectedRows(self: *Screen, row_count: u32) void {
        const drop = @min(row_count, self.history_count);
        var logical_row: u32 = 0;
        while (logical_row < drop) : (logical_row += 1) {
            const row = self.retainedRowAt(logical_row);
            if (row.wrapped) {
                self.appendHistoryBoundaryRow(row);
            } else {
                self.clearHistoryBoundary();
            }
        }
    }

    /// Resolve an oldest-first projected history row to its physical ring slot.
    fn historySlotForLogicalRow(self: *const Screen, logical_row: u32) ?u32 {
        const capacity = self.projectedCapacity();
        if (logical_row >= self.history_count or capacity == 0) return null;
        return (self.history_write_idx + logical_row) % capacity;
    }

    /// Resolve a newest-first projected history row to its physical ring slot.
    fn historySlotForRecency(self: *const Screen, history_idx: u32) ?u32 {
        if (history_idx >= self.history_count) return null;
        return self.historySlotForLogicalRow(self.history_count - 1 - history_idx);
    }

    /// Returns retained DEC line geometry by newest-first history recency.
    pub fn historyLineGeometry(self: *const Screen, history_idx: u32) LineGeometry {
        const flags = self.history_flags orelse return .single_width;
        const slot = self.historySlotForRecency(history_idx) orelse return .single_width;
        return @fromBackingInt(@intCast((flags[@intCast(slot)] & row_geometry_mask) >> row_geometry_shift));
    }

    /// Reports whether one retained history row continues into its successor.
    pub fn historyRowWrapped(self: *const Screen, history_idx: u32) bool {
        const flags = self.history_flags orelse return false;
        const slot = self.historySlotForRecency(history_idx) orelse return false;
        return flags[@intCast(slot)] & row_wrapped_bit != 0;
    }

    /// Return the physical ring slot for the next projected history row.
    fn projectedAppendSlot(self: *const Screen) u32 {
        const capacity = self.projectedCapacity();
        if (capacity == 0) return 0;
        return (self.history_write_idx + self.history_count) % capacity;
    }

    /// Return allocated projected-history row capacity.
    fn projectedCapacity(self: *const Screen) u32 {
        const flags = self.history_flags orelse return 0;
        std.debug.assert(flags.len <= std.math.maxInt(u32));
        return @intCast(flags.len);
    }

    /// Fill an assumed in-bounds row range with the current erase cell.
    fn clearRowRange(self: *Screen, row: u16, start_col: u16, end_col_exclusive: u16) void {
        const cells = self.cells orelse return;
        const start = self.rowStart(row);
        const erase_cell = self.eraseCell();
        self.clearScalarCells(
            start + start_col,
            end_col_exclusive - start_col,
        );
        @memset(
            cells[@intCast(start + @as(u32, start_col))..@intCast(start + @as(u32, end_col_exclusive))],
            erase_cell,
        );
    }

    // Clear one structural-edit range and its row state, reporting only observable mutation.
    fn clearStructuralRowRange(self: *Screen, row: u16, start_col: u16, end_col_exclusive: u16) bool {
        const cells = self.cells orelse return false;
        const start = self.rowStart(row);
        const erase = self.eraseCell();
        var changed = false;
        var col = start_col;
        while (col < end_col_exclusive) : (col += 1) {
            const cell = &cells[@intCast(start + @as(u32, col))];
            if (std.meta.eql(cell.*, erase)) continue;
            clearAcceptedTail(&self.scalars.?, start + col, cell.combining_len);
            cell.* = erase;
            changed = true;
        }
        changed = self.clearRowContinuation(row) or changed;
        if (start_col == 0 and end_col_exclusive == self.cols and self.lineGeometry(row) != .single_width) {
            self.resetLineGeometry(row);
            changed = true;
        }
        return changed;
    }

    // Erases one bounded row range and reports exact cell mutation.
    fn eraseRowRange(
        self: *Screen,
        row: u16,
        start_col: u16,
        end_col_exclusive: u16,
        selective: bool,
    ) bool {
        const cells = self.cells orelse return false;
        const start = self.rowStart(row);
        const erase_cell = self.eraseCell();
        var changed = false;
        var col = start_col;
        while (col < end_col_exclusive) : (col += 1) {
            const cell = &cells[@intCast(start + @as(u32, col))];
            if (cell.attrs.protected == .iso or (selective and cell.attrs.protected == .dec)) continue;
            if (cell.width != 1 or cell.height != 1 or cell.x != 0 or cell.y != 0) {
                changed = self.clearClusterAt(row, col, false) or changed;
                continue;
            }
            if (std.meta.eql(cell.*, erase_cell)) continue;
            clearAcceptedTail(&self.scalars.?, start + col, cell.combining_len);
            cell.* = erase_cell;
            changed = true;
        }
        return changed;
    }

    /// Reject an inverted rectangle, then clamp it to the active origin bounds.
    /// Resolves protocol rectangle coordinates against the active grid.
    pub fn rectBounds(self: *const Screen, area: RectArea) ?RectBounds {
        if (self.rows == 0 or self.cols == 0) return null;
        if (area.bottom) |bottom| if (area.top > bottom) return null;
        if (area.right) |right| if (area.left > right) return null;
        const origin = self.activeOriginBounds();
        const row_span = origin.bottom - origin.top;
        const col_span = origin.right - origin.left;
        const top = origin.top + @min(area.top, row_span);
        const bottom = origin.top + @min(area.bottom orelse row_span, row_span);
        const left = origin.left + @min(area.left, col_span);
        const right = origin.left + @min(area.right orelse col_span, col_span);
        if (top > bottom or left > right) return null;
        return .{ .top = top, .left = left, .bottom = bottom, .right = right };
    }

    // Returns the page bounds used to resolve origin-relative rectangle coordinates.
    fn activeOriginBounds(self: *const Screen) RectBounds {
        std.debug.assert(self.rows > 0 and self.cols > 0);
        const horizontal = self.origin_mode and self.left_right_margin_mode;
        return .{
            .top = if (self.origin_mode) self.scroll_top else 0,
            .left = if (horizontal) self.left_margin else 0,
            .bottom = if (self.origin_mode) self.scrollBottom() else self.rows - 1,
            .right = if (horizontal) self.right_margin else self.cols - 1,
        };
    }

    /// Construct an empty cell carrying the current erase attributes.
    fn eraseCell(self: *const Screen) Cell {
        var attrs = self.current_attrs;
        attrs.protected = .none;
        return .{ .codepoint = 0, .attrs = attrs };
    }

    fn clusterAnchorCol(self: *const Screen, row: u16, col: u16) u16 {
        const cells = self.cells orelse return col;
        if (row >= self.rows or col >= self.cols) return col;
        const cell = cells[@intCast(self.rowStart(row) + col)];
        return col -| cell.x;
    }

    // Clears one complete bounded multicell cluster intersecting an in-bounds cell.
    fn clearClusterAt(self: *Screen, row: u16, col: u16, replace_with_space: bool) bool {
        const cells = self.cells orelse return false;
        if (row >= self.rows or col >= self.cols) return false;
        const observed = cells[@intCast(self.rowStart(row) + col)];
        if (observed.width == 1 and observed.height == 1 and observed.x == 0 and observed.y == 0)
            return false;
        if (observed.width == 0 or observed.height == 0 or observed.x >= observed.width or
            observed.y >= observed.height or col < observed.x or row < observed.y)
        {
            clearAcceptedTail(
                &self.scalars.?,
                self.rowStart(row) + col,
                observed.combining_len,
            );
            cells[@intCast(self.rowStart(row) + col)] = self.eraseCell();
            return true;
        }
        const top = row - observed.y;
        const left = col - observed.x;
        const bottom = @min(self.rows, top + observed.height);
        const right = @min(self.cols, left + observed.width);
        const replacement = if (replace_with_space) Cell{
            .codepoint = ' ',
            .attrs = self.current_attrs,
        } else self.eraseCell();
        var changed = false;
        var y = top;
        while (y < bottom) : (y += 1) {
            var first: ?u16 = null;
            var last: u16 = left;
            var x = left;
            while (x < right) : (x += 1) {
                const candidate = &cells[@intCast(self.rowStart(y) + x)];
                if (candidate.width != observed.width or candidate.height != observed.height or
                    candidate.x != x - left or candidate.y != y - top)
                    continue;
                if (!std.meta.eql(candidate.*, replacement)) {
                    clearAcceptedTail(
                        &self.scalars.?,
                        self.rowStart(y) + x,
                        candidate.combining_len,
                    );
                    candidate.* = replacement;
                    if (first == null) first = x;
                    last = x;
                    changed = true;
                }
            }
        }
        return changed;
    }

    // Unconditionally clears exact cell or cluster ownership before internal
    // replacement; protocol erase protection does not govern owner cleanup.
    fn clearReplacementOwnershipAt(self: *Screen, row: u16, col: u16) bool {
        const cells = self.cells orelse return false;
        if (row >= self.rows or col >= self.cols) return false;
        const index = self.rowStart(row) + col;
        const observed = cells[@intCast(index)];
        if (observed.width != 1 or observed.height != 1 or
            observed.x != 0 or observed.y != 0)
            return self.clearClusterAt(row, col, false);
        clearAcceptedTail(&self.scalars.?, index, observed.combining_len);
        cells[@intCast(index)] = self.eraseCell();
        return !std.meta.eql(observed, cells[@intCast(index)]);
    }

    // Removes every multicell intersecting one bounded mutation rectangle.
    fn clearClustersIntersecting(
        self: *Screen,
        top: u16,
        bottom_exclusive: u16,
        left: u16,
        right_exclusive: u16,
    ) bool {
        var changed = false;
        var row = top;
        while (row < bottom_exclusive) : (row += 1) {
            var col = left;
            while (col < right_exclusive) : (col += 1)
                changed = self.clearClusterAt(row, col, false) or changed;
        }
        return changed;
    }

    fn clearNonSemanticClustersIntersecting(
        self: *Screen,
        top: u16,
        bottom_exclusive: u16,
        left: u16,
        right_exclusive: u16,
    ) bool {
        const cells = self.cells orelse return false;
        var changed = false;
        var row = top;
        while (row < bottom_exclusive) : (row += 1) {
            var col = left;
            while (col < right_exclusive) : (col += 1) {
                const cell = cells[@intCast(self.rowStart(row) + col)];
                if (isSemanticWideCell(cell)) continue;
                changed = self.clearClusterAt(row, col, false) or changed;
            }
        }
        return changed;
    }

    fn moveRowRange(self: *Screen, dst_row: u16, src_row: u16, start_col: u16, end_col_exclusive: u16) bool {
        const cells = self.cells orelse return false;
        const dst_start = self.rowStart(dst_row);
        const src_start = self.rowStart(src_row);
        const start = @as(u32, start_col);
        const end = @as(u32, end_col_exclusive);
        const dst = cells[@intCast(dst_start + start)..@intCast(dst_start + end)];
        const src = cells[@intCast(src_start + start)..@intCast(src_start + end)];
        var changed = false;
        var inline_only = true;
        for (dst, src) |destination, source| {
            if (destination.combining_len >= scalar_storage.inline_scalars or
                source.combining_len >= scalar_storage.inline_scalars)
            {
                inline_only = false;
                break;
            }
        }
        if (inline_only) {
            for (dst, src) |destination, source| {
                if (!std.meta.eql(destination, source)) {
                    changed = true;
                    break;
                }
            }
            std.mem.copyForwards(Cell, dst, src);
        } else {
            var col = start;
            while (col < end) : (col += 1) {
                const dst_index = dst_start + col;
                const src_index = src_start + col;
                const source = cells[@intCast(src_index)];
                const destination = cells[@intCast(dst_index)];
                if (!std.meta.eql(destination, source)) changed = true;

                if (self.scalars) |*storage| {
                    const source_tail = storage.tail(src_index, source.combining_len) catch
                        @panic("accepted source scalar mismatch");
                    const destination_tail = storage.tail(dst_index, destination.combining_len) catch
                        @panic("accepted destination scalar mismatch");
                    if (!std.mem.eql(u32, source_tail, destination_tail)) changed = true;
                    storage.move(
                        src_index,
                        source.combining_len,
                        dst_index,
                        destination.combining_len,
                    ) catch @panic("accepted scalar move mismatch");
                    if (source.combining_len >= scalar_storage.inline_scalars) {
                        cells[@intCast(src_index)].combining_len = scalar_storage.inline_scalars - 1;
                    }
                }
                cells[@intCast(dst_index)] = source;
            }
        }
        if (start_col == 0 and end_col_exclusive == self.cols) {
            changed = self.rowFlagsValue(dst_row) != self.rowFlagsValue(src_row) or changed;
            self.copyRowFlags(dst_row, src_row);
        } else {
            changed = self.clearRowContinuation(dst_row) or changed;
        }
        return changed;
    }

    fn rowFlagsValue(self: *const Screen, row: u16) u8 {
        const flags = self.row_flags orelse return 0;
        const idx = self.rowWrapIndex(row) orelse return 0;
        return flags[@intCast(idx)];
    }

    fn copyRowFlags(self: *Screen, dst_row: u16, src_row: u16) void {
        const flags = self.row_flags orelse return;
        const dst = self.rowWrapIndex(dst_row) orelse return;
        const src = self.rowWrapIndex(src_row) orelse return;
        flags[@intCast(dst)] = flags[@intCast(src)];
    }
};

// =============================================================================
// Logical text projection helpers
// =============================================================================

fn screenColCount(value: u16) u32 {
    return value;
}

fn cloneLogicalLine(
    allocator: std.mem.Allocator,
    cells: []const ScreenCell,
    scalars: ?*const scalar_storage.Storage,
    scalar_start: usize,
) std.mem.Allocator.Error!LogicalLine {
    var line = LogicalLine{};
    errdefer line.deinit(allocator);
    try line.cells.appendSlice(allocator, cells);
    line.scalars = try cloneLineScalars(
        allocator,
        cells,
        scalars,
        scalar_start,
    );
    return line;
}

fn cellsHaveExternalScalars(cells: []const ScreenCell) bool {
    for (cells) |cell| {
        if (sidecarCount(cell) != 0) return true;
    }
    return false;
}

fn cloneLineScalars(
    allocator: std.mem.Allocator,
    cells: []const ScreenCell,
    source: ?*const scalar_storage.Storage,
    source_start: usize,
) std.mem.Allocator.Error!?scalar_storage.Storage {
    if (!cellsHaveExternalScalars(cells)) return null;
    var result = scalar_storage.Storage.init(
        allocator,
        cells.len,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCapacity => unreachable,
    };
    errdefer result.deinit();
    for (cells, 0..) |cell, index| {
        if (cell.combining_len <= scalar_storage.inline_scalars - 1)
            continue;
        const retained = source orelse
            @panic("accepted scalar owner missing");
        const tail = acceptedTail(
            retained,
            source_start + index,
            cell.combining_len,
        );
        result.set(index, 0, tail) catch |err| switch (err) {
            error.InvalidRange => @panic("accepted scalar range mismatch"),
            error.ScalarCapacity => @panic("cloned scalar capacity mismatch"),
        };
    }
    return result;
}

fn appendLogicalCells(
    allocator: std.mem.Allocator,
    line: *LogicalLine,
    appended: []const ScreenCell,
    appended_scalars: *const scalar_storage.Storage,
    appended_start: usize,
) std.mem.Allocator.Error!void {
    if (appended.len == 0) return;
    const old_len = line.cells.items.len;
    const new_len = std.math.add(usize, old_len, appended.len) catch
        return error.OutOfMemory;
    var candidate = LogicalLine{
        .cursor_offset = line.cursor_offset,
    };
    errdefer candidate.deinit(allocator);
    try candidate.cells.ensureTotalCapacity(allocator, new_len);
    candidate.cells.appendSliceAssumeCapacity(line.cells.items);
    candidate.cells.appendSliceAssumeCapacity(appended);
    candidate.scalars = scalar_storage.Storage.init(
        allocator,
        new_len,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCapacity => unreachable,
    };
    if (line.scalars) |*source| {
        copyScalarCells(
            source,
            line.cells.items,
            0,
            &candidate.scalars.?,
            0,
            old_len,
        ) catch @panic("logical scalar clone mismatch");
    }
    copyScalarCells(
        appended_scalars,
        appended,
        appended_start,
        &candidate.scalars.?,
        old_len,
        appended.len,
    ) catch @panic("visible scalar clone mismatch");
    line.deinit(allocator);
    line.* = candidate;
    candidate = .{};
}

fn copyScalarCells(
    source: *const scalar_storage.Storage,
    cells: []const ScreenCell,
    source_start: usize,
    destination: *scalar_storage.Storage,
    destination_start: usize,
    count: usize,
) error{ InvalidRange, ScalarCapacity }!void {
    if (count > cells.len) return error.InvalidRange;
    var copied: usize = 0;
    errdefer {
        var rollback: usize = 0;
        while (rollback < copied) : (rollback += 1) {
            const cell = cells[rollback];
            destination.clear(
                destination_start + rollback,
                cell.combining_len,
            ) catch @panic("candidate scalar rollback mismatch");
        }
    }
    while (copied < count) : (copied += 1) {
        const cell = cells[copied];
        try scalar_storage.Storage.copy(
            source,
            source_start + copied,
            cell.combining_len,
            destination,
            destination_start + copied,
            0,
        );
    }
}

const HistoryBoundaryWriter = struct {
    storage: []u8,
    stored: usize,
    total: usize,

    fn write(self: *HistoryBoundaryWriter, bytes: []const u8) void {
        if (self.stored < self.storage.len) {
            const copied = @min(bytes.len, self.storage.len - self.stored);
            @memcpy(self.storage[self.stored..][0..copied], bytes[0..copied]);
            self.stored += copied;
        }
        self.total = std.math.add(usize, self.total, bytes.len) catch
            @panic("history boundary text byte count overflow");
        std.debug.assert(self.stored == @min(self.total, self.storage.len));
    }
};

const OutputTextWriter = struct {
    storage: []u8,
    start: u32,
    count: usize = 0,

    fn init(storage: []u8, start: u32) OutputTextWriter {
        std.debug.assert(storage.len == Screen.retained_output_bytes_max);
        std.debug.assert(start < storage.len);
        return .{ .storage = storage, .start = start };
    }

    fn write(self: *OutputTextWriter, bytes: []const u8) void {
        std.debug.assert(bytes.len <= self.storage.len - self.count);
        if (bytes.len == 0) return;
        const offset = (@as(usize, self.start) + self.count) % self.storage.len;
        const first_len = @min(bytes.len, self.storage.len - offset);
        @memcpy(self.storage[offset..][0..first_len], bytes[0..first_len]);
        const second_len = bytes.len - first_len;
        if (second_len != 0) {
            @memcpy(self.storage[0..second_len], bytes[first_len..]);
        }
        self.count += bytes.len;
    }
};

const RetainedTextWriter = union(enum) {
    history_boundary: *HistoryBoundaryWriter,
    output: *OutputTextWriter,

    fn write(self: RetainedTextWriter, bytes: []const u8) void {
        switch (self) {
            .history_boundary => |writer| writer.write(bytes),
            .output => |writer| writer.write(bytes),
        }
    }
};

fn externalCellScalars(
    storage: ?*const scalar_storage.Storage,
    cell_index: usize,
    cell: ScreenCell,
) []const u32 {
    const expected = sidecarCount(cell);
    if (expected == 0) {
        if (storage) |owner| {
            if (!owner.validRange(cell_index, cell.combining_len))
                @panic("accepted output scalar range/count mismatch");
        }
        return &.{};
    }
    const owner = storage orelse
        @panic("accepted output scalar owner missing");
    const tail = acceptedTail(owner, cell_index, cell.combining_len);
    std.debug.assert(tail.len == expected);
    return tail;
}

fn writeScalarText(writer: RetainedTextWriter, scalar: u32) void {
    var encoded: [4]u8 = undefined;
    const codepoint = std.math.cast(u21, scalar) orelse unreachable;
    const length = std.unicode.utf8Encode(codepoint, &encoded) catch unreachable;
    writer.write(encoded[0..length]);
}

fn writeCellText(
    writer: RetainedTextWriter,
    cell: ScreenCell,
    external: []const u32,
) void {
    if (isCellContinuation(cell)) return;
    const direct = @min(@as(usize, cell.combining_len), cell.combining.len);
    std.debug.assert(direct + external.len == cell.combining_len);
    writeScalarText(writer, if (cell.codepoint == 0) ' ' else cell.codepoint);
    for (cell.combining[0..direct]) |combining| writeScalarText(writer, combining);
    for (external) |combining| writeScalarText(writer, combining);
}

fn writeRetainedRowText(
    screen: *const Screen,
    row: Screen.RetainedRow,
    writer: RetainedTextWriter,
) void {
    const content_len = screen.retainedRowContentLen(row);
    var col: u16 = 0;
    while (col < content_len) : (col += 1) {
        const cell = row.cells[col];
        writeCellText(
            writer,
            cell,
            externalCellScalars(row.scalars, row.scalar_start + col, cell),
        );
    }
}

fn writeOpenOutputLine(screen: *const Screen, writer: *OutputTextWriter) void {
    const text_writer = RetainedTextWriter{ .output = writer };
    const range = screen.currentRetainedLineRange();
    if (range.start == 0 and screen.history_boundary_active) {
        std.debug.assert(screen.history_boundary_total <= Screen.retained_output_bytes_max);
        std.debug.assert(screen.history_boundary_stored == screen.history_boundary_total);
        writer.write(screen.history_boundary_text.?[0..screen.history_boundary_stored]);
    }
    var row_index = range.start;
    while (row_index < range.end) : (row_index += 1) {
        writeRetainedRowText(screen, screen.retainedRowAt(row_index), text_writer);
    }
}

fn appendScalarTextBounded(
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),
    scalar: u32,
    limit: usize,
) (std.mem.Allocator.Error || error{LineTooLong})!void {
    var encoded: [4]u8 = undefined;
    const value = std.math.cast(u21, scalar) orelse unreachable;
    const length = std.unicode.utf8Encode(value, &encoded) catch unreachable;
    if (length > limit -| bytes.items.len) return error.LineTooLong;
    try bytes.appendSlice(allocator, encoded[0..length]);
}

fn appendCellTextBounded(
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),
    cell: ScreenCell,
    external: []const u32,
    limit: usize,
) (std.mem.Allocator.Error || error{LineTooLong})!void {
    if (isCellContinuation(cell)) return;
    try appendScalarTextBounded(
        allocator,
        bytes,
        if (cell.codepoint == 0) ' ' else cell.codepoint,
        limit,
    );
    const direct_count = @min(@as(usize, cell.combining_len), cell.combining.len);
    for (cell.combining[0..direct_count]) |scalar|
        try appendScalarTextBounded(allocator, bytes, scalar, limit);
    for (external) |scalar|
        try appendScalarTextBounded(allocator, bytes, scalar, limit);
    std.debug.assert(direct_count + external.len == cell.combining_len);
}

fn scalarTextByteCount(scalar: u32) usize {
    var encoded: [4]u8 = undefined;
    const value = std.math.cast(u21, scalar) orelse unreachable;
    return std.unicode.utf8Encode(value, &encoded) catch unreachable;
}

fn cellTextByteCount(cell: ScreenCell, external: []const u32) usize {
    if (isCellContinuation(cell)) return 0;
    var count = scalarTextByteCount(if (cell.codepoint == 0) ' ' else cell.codepoint);
    const direct_count = @min(@as(usize, cell.combining_len), cell.combining.len);
    for (cell.combining[0..direct_count]) |scalar| {
        count = std.math.add(usize, count, scalarTextByteCount(scalar)) catch
            @panic("resident logical output byte count overflow");
    }
    for (external) |scalar| {
        count = std.math.add(usize, count, scalarTextByteCount(scalar)) catch
            @panic("resident logical output byte count overflow");
    }
    std.debug.assert(direct_count + external.len == cell.combining_len);
    return count;
}

fn retainedRowTextByteCount(screen: *const Screen, row: Screen.RetainedRow) usize {
    var count: usize = 0;
    const content_len = screen.retainedRowContentLen(row);
    var col: u16 = 0;
    while (col < content_len) : (col += 1) {
        const cell = row.cells[col];
        const external = externalCellScalars(row.scalars, row.scalar_start + col, cell);
        count = std.math.add(usize, count, cellTextByteCount(cell, external)) catch
            @panic("resident logical output byte count overflow");
    }
    return count;
}

fn openOutputLineByteCount(screen: *const Screen) usize {
    const range = screen.currentRetainedLineRange();
    var count: usize = if (range.start == 0 and screen.history_boundary_active)
        screen.history_boundary_total
    else
        0;
    var row_index = range.start;
    while (row_index < range.end) : (row_index += 1) {
        count = std.math.add(
            usize,
            count,
            retainedRowTextByteCount(screen, screen.retainedRowAt(row_index)),
        ) catch @panic("resident logical output byte count overflow");
    }
    return count;
}

/// Exact failures while copying one unfinished logical output line.
pub const CopyOpenOutputLineError = error{ OutOfMemory, LineTooLong };

// Appends one retained row to caller-owned bounded output.
fn appendRetainedRowTextBounded(
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),
    screen: *const Screen,
    row: Screen.RetainedRow,
    limit: usize,
) CopyOpenOutputLineError!void {
    const content_len = screen.retainedRowContentLen(row);
    var col: u16 = 0;
    while (col < content_len) : (col += 1) {
        const cell = row.cells[col];
        try appendCellTextBounded(
            allocator,
            bytes,
            cell,
            externalCellScalars(row.scalars, row.scalar_start + col, cell),
            limit,
        );
    }
}

/// Copies the current unfinished logical line into caller-owned storage.
pub fn copyOpenOutputLine(
    allocator: std.mem.Allocator,
    screen: *const Screen,
    limit: usize,
) CopyOpenOutputLineError![]u8 {
    var bytes = std.ArrayList(u8).empty;
    errdefer bytes.deinit(allocator);
    const range = screen.currentRetainedLineRange();
    if (range.start == 0 and screen.history_boundary_active) {
        if (screen.history_boundary_total > limit) return error.LineTooLong;
        std.debug.assert(screen.history_boundary_stored == screen.history_boundary_total);
        try bytes.appendSlice(
            allocator,
            screen.history_boundary_text.?[0..screen.history_boundary_stored],
        );
    }
    var row_index = range.start;
    while (row_index < range.end) : (row_index += 1) {
        try appendRetainedRowTextBounded(
            allocator,
            &bytes,
            screen,
            screen.retainedRowAt(row_index),
            limit,
        );
    }
    return bytes.toOwnedSlice(allocator);
}

// =============================================================================
// Cell rendition and semantic value model
// =============================================================================

fn decodeExtendedColor(
    operands: Screen.SgrOperands,
    idx: *u8,
) ?ScreenColor {
    const params = operands.values;
    const next = idx.* + 1;
    if (next >= params.len) return null;
    const mode = params[idxOf(next)];
    if (operands.colonAfter(idx.*)) return decodeColonColor(operands, idx, mode);
    if (mode == 5) {
        if (idx.* + 2 >= params.len) {
            idx.* = @intCast(params.len - 1);
            return null;
        }
        idx.* += 2;
        return .indexed(clampByte(params[idxOf(idx.*)]));
    }
    if (mode == 2) {
        if (idx.* + 4 >= params.len) {
            idx.* = @intCast(params.len - 1);
            return null;
        }
        idx.* += 4;
        return ScreenColor.rgb(.{
            .r = clampByte(params[idxOf(idx.* - 2)]),
            .g = clampByte(params[idxOf(idx.* - 1)]),
            .b = clampByte(params[idxOf(idx.*)]),
        });
    }
    idx.* += 1;
    return null;
}

// Decodes one colon-delimited color group and consumes every owned subparameter.
fn decodeColonColor(
    operands: Screen.SgrOperands,
    idx: *u8,
    mode: i32,
) ?ScreenColor {
    const params = operands.values;
    var end = idx.*;
    while (end + 1 < params.len and operands.colonAfter(end)) end += 1;
    defer idx.* = end;

    const count = end - idx.* + 1;
    if (mode == 5) {
        if (count < 3) return null;
        return .indexed(clampByte(params[idxOf(idx.* + 2)]));
    }
    if (mode != 2 or count < 5) return null;

    // Five fields are the widespread 2:R:G:B form. Six or more carry a
    // color-space field before RGB; unsupported trailing tolerance fields are ignored.
    const red = idx.* + if (count == 5) @as(u8, 2) else 3;
    if (red + 2 > end) return null;
    return ScreenColor.rgb(.{
        .r = clampByte(params[idxOf(red)]),
        .g = clampByte(params[idxOf(red + 1)]),
        .b = clampByte(params[idxOf(red + 2)]),
    });
}

fn idxOf(value: u8) usize {
    return @intCast(value);
}

fn clampByte(value: i32) u8 {
    return @intCast(@max(0, @min(255, value)));
}

fn screenAnsi16Color(idx: u8) ScreenColor {
    return switch (idx) {
        0...15 => .indexed(idx),
        else => initial_cell_attrs.fg,
    };
}

// Identifies the supported terminal underline presentation styles.
const ScreenUnderlineStyle = enum(u3) {
    straight,
    double,
    curly,
    dotted,
    dashed,
};

// Identifies the baseline displacement retained for one terminal cell.
const ScreenBaseline = enum(u2) {
    normal,
    raised,
    lowered,
};

/// Distinguishes ISO guarded areas from DEC selective-erase protection.
pub const ScreenProtection = enum(u2) {
    none,
    iso,
    dec,
};

/// Stores one cell's font, baseline, style, colors, protection, and hyperlink identity.
pub const ScreenCellAttrs = struct {
    fg: ScreenColor,
    bg: ScreenColor,
    font: u4,
    baseline: ScreenBaseline,
    bold: bool,
    dim: bool,
    italic: bool,
    blink: bool,
    blink_fast: bool,
    reverse: bool,
    invisible: bool,
    underline: bool,
    strikethrough: bool,
    underline_style: ScreenUnderlineStyle,
    underline_color: ScreenColor,
    protected: ScreenProtection,
    link_id: u32,
};

// Stores one bounded Unicode cluster, ordinary or OSC 66 placement, and complete attributes.
const ScreenCell = struct {
    codepoint: u32,
    combining_len: u8 = 0,
    combining: [3]u32 = .{ 0, 0, 0 },
    width: u8 = 1,
    height: u8 = 1,
    x: u8 = 0,
    y: u8 = 0,
    subscale_n: u4 = 0,
    subscale_d: u4 = 0,
    vertical_align: u2 = 0,
    horizontal_align: u2 = 0,
    semantic_width: bool = false,
    attrs: ScreenCellAttrs,
};

fn sidecarCount(cell: ScreenCell) usize {
    return @as(usize, cell.combining_len) -| (scalar_storage.inline_scalars - 1);
}

// Retains the complete bounded graphic cluster consumed by REP.
const LastGraphic = struct {
    codepoint: u21,
    width: u8 = 1,
    combining_len: u8 = 0,
    combining: [scalar_storage.maximum_scalars - 1]u21 =
        @splat(0),
};

fn isCellContinuation(cell: ScreenCell) bool {
    return cell.x != 0 or cell.y != 0;
}

fn isSemanticWideLead(cell: ScreenCell) bool {
    return cell.semantic_width and cell.width == 2 and
        cell.height == 1 and cell.x == 0 and cell.y == 0;
}

fn isSemanticWideCell(cell: ScreenCell) bool {
    return cell.semantic_width and cell.width == 2 and
        cell.height == 1 and cell.x < 2 and cell.y == 0;
}

// Provides immutable default terminal cell attributes.
const initial_cell_attrs = ScreenCellAttrs{
    .fg = default_cell_foreground,
    .bg = default_cell_background,
    .font = 0,
    .baseline = .normal,
    .bold = false,
    .dim = false,
    .italic = false,
    .blink = false,
    .blink_fast = false,
    .reverse = false,
    .invisible = false,
    .underline = false,
    .strikethrough = false,
    .underline_style = .straight,
    .underline_color = default_cell_underline_color,
    .protected = .none,
    .link_id = 0,
};

// Provides the blank default cell used for clearing and allocation.
const blank_cell = ScreenCell{
    .codepoint = 0,
    .attrs = initial_cell_attrs,
};

// =============================================================================
// Unicode cell and projected-history proofs
// =============================================================================

test "screen retains twenty four scalars and REP owns an independent copy" {
    var screen = try Screen.initWithCells(std.testing.allocator, 1, 4);
    defer screen.deinit(std.testing.allocator);
    screen.writeCell('a');
    var scalar_value: u21 = 0x0300;
    while (scalar_value < 0x0300 + 23) : (scalar_value += 1)
        screen.writeCell(scalar_value);

    var first_storage: [scalar_storage.maximum_scalars]u32 = undefined;
    const first = screen.cellScalarsAt(0, 0, &first_storage);
    try std.testing.expectEqual(@as(usize, 24), first.len);
    try std.testing.expectEqual(@as(u32, 'a'), first[0]);
    for (first[1..], 0x0300..) |value, expected|
        try std.testing.expectEqual(@as(u32, @intCast(expected)), value);

    const before = screen.cellInfoAt(0, 0);
    const before_tail = screen.scalars.?.ranges[0];
    screen.writeCell(0x0317);
    try std.testing.expectEqualDeep(before, screen.cellInfoAt(0, 0));
    try std.testing.expectEqual(before_tail, screen.scalars.?.ranges[0]);

    try std.testing.expect(screen.repeatPreceding(1));
    var repeated_storage: [scalar_storage.maximum_scalars]u32 = undefined;
    const repeated = screen.cellScalarsAt(0, 1, &repeated_storage);
    try std.testing.expectEqualSlices(u32, first, repeated);
    try std.testing.expect(screen.scalars.?.ranges[0] != screen.scalars.?.ranges[1]);
}

test "Unicode 17 semantic width owns canonical lead and continuation cells" {
    var screen = try Screen.initWithCells(std.testing.allocator, 2, 4);
    defer screen.deinit(std.testing.allocator);

    screen.writeCell(0x754c);
    try std.testing.expectEqual(@as(u32, 0x754c), screen.cells.?[0].codepoint);
    try std.testing.expectEqual(@as(u8, 2), screen.cells.?[0].width);
    try std.testing.expectEqual(@as(u32, 0), screen.cells.?[1].codepoint);
    try std.testing.expectEqual(@as(u8, 0), screen.cells.?[1].combining_len);
    try std.testing.expectEqual(@as(u8, 2), screen.cells.?[1].width);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[1].x);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor.col);

    screen.writeCell('a');
    try std.testing.expectEqual(@as(u32, 'a'), screen.cells.?[2].codepoint);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[2].width);
}

test "Unicode 17 grapheme transitions admit zero width scalars exactly" {
    var screen = try Screen.initWithCells(std.testing.allocator, 1, 4);
    defer screen.deinit(std.testing.allocator);

    screen.writeCell('a');
    screen.writeCell(0x0301);
    var scalars: [scalar_storage.maximum_scalars]u32 = undefined;
    try std.testing.expectEqualSlices(
        u32,
        &.{ 'a', 0x0301 },
        screen.cellScalarsAt(0, 0, &scalars),
    );
    const before = screen.cells.?[0];
    screen.writeCell(0x200b);
    try std.testing.expectEqualDeep(before, screen.cells.?[0]);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor.col);
}

test "Unicode 17 variation selectors transactionally change emoji occupancy" {
    var screen = try Screen.initWithCells(std.testing.allocator, 1, 4);
    defer screen.deinit(std.testing.allocator);

    screen.writeCell(0x263a);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[0].width);
    screen.writeCell(0xfe0f);
    try std.testing.expectEqual(@as(u8, 2), screen.cells.?[0].width);
    try std.testing.expect(screen.cells.?[0].semantic_width);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[1].x);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor.col);

    screen.writeCell(0xfe0e);
    try std.testing.expectEqual(@as(u8, 2), screen.cells.?[0].width);

    screen.clearVisibleCells();
    screen.cursor.setPositionByClient(0, 0);
    screen.writeCell(0x1f610);
    screen.writeCell(0xfe0e);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[0].width);
    try std.testing.expectEqualDeep(blank_cell, screen.cells.?[1]);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor.col);

    screen.clearVisibleCells();
    screen.cursor.setPositionByClient(0, 0);
    screen.writeCell(0x25b6);
    screen.writeCell(0xfe0f);
    screen.writeCell(0xfe0e);
    try std.testing.expectEqual(@as(u8, 2), screen.cells.?[0].width);
}

test "Unicode 17 presentation widening relocates the last-column cluster" {
    var screen = try Screen.initWithCells(std.testing.allocator, 2, 3);
    defer screen.deinit(std.testing.allocator);
    screen.writeCell('*');
    screen.writeCell(0xfe0f);
    screen.writeCell('*');
    screen.writeCell(0xfe0f);

    try std.testing.expectEqual(@as(u8, 2), screen.cells.?[0].width);
    try std.testing.expectEqualDeep(blank_cell, screen.cells.?[2]);
    try std.testing.expectEqual(@as(u32, '*'), screen.cells.?[3].codepoint);
    try std.testing.expectEqual(@as(u8, 2), screen.cells.?[3].width);
    try std.testing.expect(screen.cells.?[3].semantic_width);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[4].x);
    try std.testing.expectEqual(@as(u16, 1), screen.cursor.row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor.col);
}

test "VS16 right-edge relocation without autowrap preserves exact ownership" {
    var screen = try Screen.initWithCellsAndHistory(
        std.testing.allocator,
        2,
        4,
        2,
    );
    defer screen.deinit(std.testing.allocator);
    screen.auto_wrap = false;

    const destination: usize = 2;
    var outgoing_tail: [scalar_storage.maximum_tail_scalars]u32 = undefined;
    for (&outgoing_tail, 0..) |*scalar, index|
        scalar.* = 0x0400 + @as(u32, @intCast(index));
    try screen.scalars.?.set(destination, 0, &outgoing_tail);
    var outgoing = blank_cell;
    outgoing.codepoint = 'x';
    outgoing.combining = .{ 0x0300, 0x0301, 0x0302 };
    outgoing.combining_len = scalar_storage.maximum_scalars - 1;
    outgoing.attrs.protected = .iso;
    screen.cells.?[destination] = outgoing;

    screen.cursor.setPositionByClient(0, 3);
    screen.writeCell(0x263a);
    screen.writeCell(0xfe0f);

    try std.testing.expectEqual(@as(u32, 0x263a), screen.cells.?[2].codepoint);
    try std.testing.expectEqual(@as(u8, 2), screen.cells.?[2].width);
    try std.testing.expect(screen.cells.?[2].semantic_width);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[3].x);
    try std.testing.expect(screen.cells.?[3].semantic_width);
    var accepted: [scalar_storage.maximum_scalars]u32 = undefined;
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x263a, 0xfe0f },
        screen.cellScalarsAt(0, 2, &accepted),
    );
    try std.testing.expectEqual(scalar_storage.Range.none, screen.scalars.?.ranges[3]);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor.row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor.col);
    try std.testing.expect(!screen.wrap_pending);
    try std.testing.expectEqual(@as(u32, 0), screen.history_count);
    try std.testing.expect(!screen.rowWrapped(0));
}

test "VS16 non-wrapping relocation clears protected OSC 66 ownership" {
    var screen = try Screen.initWithCells(std.testing.allocator, 2, 4);
    defer screen.deinit(std.testing.allocator);
    screen.auto_wrap = false;

    var osc_lead = blank_cell;
    osc_lead.codepoint = 'o';
    osc_lead.height = 2;
    osc_lead.attrs.protected = .iso;
    screen.cells.?[2] = osc_lead;
    var osc_continuation = blank_cell;
    osc_continuation.height = 2;
    osc_continuation.y = 1;
    osc_continuation.attrs.protected = .iso;
    screen.cells.?[6] = osc_continuation;

    screen.cursor.setPositionByClient(0, 3);
    screen.writeCell(0x263a);
    screen.writeCell(0xfe0f);

    try std.testing.expectEqual(@as(u32, 0x263a), screen.cells.?[2].codepoint);
    try std.testing.expect(screen.cells.?[2].semantic_width);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[3].x);
    try std.testing.expectEqualDeep(blank_cell, screen.cells.?[6]);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor.row);
    try std.testing.expectEqual(@as(u16, 3), screen.cursor.col);
    try std.testing.expect(!screen.wrap_pending);
}

test "VS16 wrapping relocation clears destination scalar and OSC 66 ownership" {
    var screen = try Screen.initWithCellsAndHistory(
        std.testing.allocator,
        2,
        4,
        2,
    );
    defer screen.deinit(std.testing.allocator);

    const destination = screen.rowStart(1);
    var outgoing_tail: [scalar_storage.maximum_tail_scalars]u32 = undefined;
    for (&outgoing_tail, 0..) |*value, index|
        value.* = 0x0400 + @as(u32, @intCast(index));
    try screen.scalars.?.set(destination, 0, &outgoing_tail);
    var outgoing = blank_cell;
    outgoing.codepoint = 'x';
    outgoing.combining = .{ 0x0300, 0x0301, 0x0302 };
    outgoing.combining_len = scalar_storage.maximum_scalars - 1;
    outgoing.attrs.protected = .iso;
    screen.cells.?[@intCast(destination)] = outgoing;
    var osc_lead = blank_cell;
    osc_lead.codepoint = 'o';
    osc_lead.width = 2;
    osc_lead.attrs.protected = .iso;
    screen.cells.?[@intCast(destination + 1)] = osc_lead;
    var osc_continuation = blank_cell;
    osc_continuation.width = 2;
    osc_continuation.x = 1;
    osc_continuation.attrs.protected = .iso;
    screen.cells.?[@intCast(destination + 2)] = osc_continuation;

    screen.cursor.setPositionByClient(0, 3);
    screen.writeCell(0x263a);
    screen.writeCell(0xfe0f);

    try std.testing.expectEqual(@as(u32, 0x263a), screen.cells.?[@intCast(destination)].codepoint);
    try std.testing.expect(screen.cells.?[@intCast(destination)].semantic_width);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[@intCast(destination + 1)].x);
    try std.testing.expectEqualDeep(blank_cell, screen.cells.?[@intCast(destination + 2)]);
    var accepted: [scalar_storage.maximum_scalars]u32 = undefined;
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x263a, 0xfe0f },
        screen.cellScalarsAt(1, 0, &accepted),
    );
    try std.testing.expectEqual(scalar_storage.Range.none, screen.scalars.?.ranges[3]);
    try std.testing.expectEqual(scalar_storage.Range.none, screen.scalars.?.ranges[destination + 1]);
    try std.testing.expectEqual(scalar_storage.Range.none, screen.scalars.?.ranges[destination + 2]);
    try std.testing.expect(screen.rowWrapped(0));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor.row);
    try std.testing.expectEqual(@as(u16, 2), screen.cursor.col);
    try std.testing.expectEqual(@as(u32, 0), screen.history_count);
}

test "VS16 semantic width survives history restoration reflow and resize" {
    var screen = try Screen.initWithCellsAndHistory(
        std.testing.allocator,
        2,
        4,
        4,
    );
    defer screen.deinit(std.testing.allocator);
    screen.writeCell(0x263a);
    screen.writeCell(0xfe0f);
    screen.cursor.setColByClient(0);
    screen.lineFeed();
    screen.lineFeed();

    try std.testing.expectEqual(@as(u8, 2), screen.historyCellAt(0, 0).width);
    try std.testing.expect(screen.historyCellAt(0, 0).semantic_width);
    try std.testing.expect(screen.scrollDownFromHistory(1));
    var lead: usize = 0;
    while (lead < screen.cells.?.len and screen.cells.?[lead].codepoint != 0x263a) : (lead += 1) {}
    try std.testing.expect(lead < screen.cells.?.len);
    try std.testing.expect(screen.cells.?[lead].semantic_width);
    try screen.resize(std.testing.allocator, 3, 3);
    lead = 0;
    while (lead < screen.cells.?.len and screen.cells.?[lead].codepoint != 0x263a) : (lead += 1) {}
    try std.testing.expect(lead + 1 < screen.cells.?.len);
    try std.testing.expectEqual(@as(u8, 2), screen.cells.?[lead].width);
    try std.testing.expect(screen.cells.?[lead].semantic_width);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[lead + 1].x);
    var accepted: [scalar_storage.maximum_scalars]u32 = undefined;
    try std.testing.expectEqualSlices(
        u32,
        &.{ 0x263a, 0xfe0f },
        screen.cellScalarsAt(
            @intCast(lead / screen.cols),
            @intCast(lead % screen.cols),
            &accepted,
        ),
    );
}

test "REP preserves Unicode semantic occupancy independently" {
    var screen = try Screen.initWithCells(std.testing.allocator, 1, 4);
    defer screen.deinit(std.testing.allocator);
    screen.writeCell(0x754c);
    try std.testing.expect(screen.repeatPreceding(1));

    try std.testing.expectEqual(@as(u32, 0x754c), screen.cells.?[2].codepoint);
    try std.testing.expectEqual(@as(u8, 2), screen.cells.?[2].width);
    try std.testing.expectEqual(@as(u32, 0), screen.cells.?[3].codepoint);
    try std.testing.expectEqual(@as(u8, 1), screen.cells.?[3].x);

    screen.clearVisibleCells();
    screen.cursor.setPositionByClient(0, 0);
    screen.writeCell('a');
    try std.testing.expect(screen.repeatPreceding(1));
    try std.testing.expect(!screen.cells.?[1].semantic_width);
}

test "Unicode semantic occupancy and scalars survive history restoration" {
    var screen = try Screen.initWithCellsAndHistory(
        std.testing.allocator,
        2,
        4,
        4,
    );
    defer screen.deinit(std.testing.allocator);
    screen.writeCell(0x754c);
    screen.cursor.setColByClient(0);
    screen.lineFeed();
    screen.lineFeed();

    try std.testing.expectEqual(@as(u32, 1), screen.historyCount());
    try std.testing.expectEqual(@as(u8, 2), screen.historyCellAt(0, 0).width);
    try std.testing.expectEqual(@as(u8, 1), screen.historyCellAt(0, 1).x);
    try std.testing.expect(screen.scrollDownFromHistory(1));
    try std.testing.expectEqual(@as(u32, 0x754c), screen.cellInfoAt(0, 0).codepoint);
    try std.testing.expectEqual(@as(u8, 2), screen.cellInfoAt(0, 0).width);
    try std.testing.expectEqual(@as(u8, 1), screen.cellInfoAt(0, 1).x);
}

test "Unicode semantic occupancy reflows without splitting a wide cluster" {
    var screen = try Screen.initWithCells(std.testing.allocator, 2, 4);
    defer screen.deinit(std.testing.allocator);
    screen.writeText("aa");
    screen.writeCell(0x754c);
    var scalar_value: u21 = 0x0300;
    while (scalar_value < 0x0300 + 23) : (scalar_value += 1)
        screen.writeCell(scalar_value);

    try screen.resize(std.testing.allocator, 3, 3);
    try std.testing.expectEqual(@as(u32, 'a'), screen.cellInfoAt(0, 0).codepoint);
    try std.testing.expectEqual(@as(u32, 'a'), screen.cellInfoAt(0, 1).codepoint);
    try std.testing.expectEqualDeep(blank_cell, screen.cellInfoAt(0, 2));
    try std.testing.expectEqual(@as(u32, 0x754c), screen.cellInfoAt(1, 0).codepoint);
    try std.testing.expectEqual(@as(u8, 2), screen.cellInfoAt(1, 0).width);
    try std.testing.expectEqual(@as(u8, 1), screen.cellInfoAt(1, 1).x);
    var scalars: [scalar_storage.maximum_scalars]u32 = undefined;
    try std.testing.expectEqual(
        @as(usize, scalar_storage.maximum_scalars),
        screen.cellScalarsAt(1, 0, &scalars).len,
    );
}

test "one-column resize transactionally omits unrepresentable semantic widths" {
    var screen = try oneColumnOmissionFixture();
    defer screen.deinit(std.testing.allocator);

    const cells_before = try std.testing.allocator.dupe(ScreenCell, screen.cells.?);
    defer std.testing.allocator.free(cells_before);
    const ranges_before = try std.testing.allocator.dupe(
        scalar_storage.Range,
        screen.scalars.?.ranges,
    );
    defer std.testing.allocator.free(ranges_before);
    const pages_before = try std.testing.allocator.dupe(
        u8,
        std.mem.sliceAsBytes(screen.scalars.?.pages),
    );
    defer std.testing.allocator.free(pages_before);
    const history_before = try copyProjectedHistory(std.testing.allocator, &screen);
    defer std.testing.allocator.free(history_before);
    const cursor_before = screen.cursor;
    const history_count_before = screen.history_count;

    var discarded = try screen.prepareResize(std.testing.allocator, 4, 1);
    try std.testing.expectEqualSlices(ScreenCell, cells_before, screen.cells.?);
    try std.testing.expectEqualSlices(
        scalar_storage.Range,
        ranges_before,
        screen.scalars.?.ranges,
    );
    try std.testing.expectEqualSlices(
        u8,
        pages_before,
        std.mem.sliceAsBytes(screen.scalars.?.pages),
    );
    const history_after_discard = try copyProjectedHistory(std.testing.allocator, &screen);
    defer std.testing.allocator.free(history_after_discard);
    try std.testing.expectEqualSlices(ScreenCell, history_before, history_after_discard);
    try std.testing.expectEqualDeep(cursor_before, screen.cursor);
    try std.testing.expectEqual(history_count_before, screen.history_count);
    discarded.deinit(std.testing.allocator);

    var replacement = try screen.prepareResize(std.testing.allocator, 4, 1);
    std.mem.swap(Screen, &screen, &replacement);
    replacement.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u16, 1), screen.cols);
    try std.testing.expect(screen.cursor.col < screen.cols);
    try std.testing.expect(!containsCodepoint(&screen, 0x754c));
    try std.testing.expect(!containsCodepoint(&screen, 0x8a9e));
    try std.testing.expect(containsCodepoint(&screen, 'A'));
    try std.testing.expect(containsCodepoint(&screen, 'B'));
    for (screen.cells.?, 0..) |cell, index| {
        const retained = try screen.scalars.?.validate(index, cell.combining_len);
        try std.testing.expectEqual(sidecarCount(cell), retained);
    }
    if (screen.history_scalars) |*storage| {
        var logical_row: u32 = 0;
        while (logical_row < screen.history_count) : (logical_row += 1) {
            const slot = screen.historySlotForLogicalRow(logical_row) orelse unreachable;
            const base = slot * @as(u32, screen.cols);
            const row = screen.history.?[@intCast(base)..@intCast(base + screen.cols)];
            for (row, 0..) |cell, col| {
                const retained = try storage.validate(base + col, cell.combining_len);
                try std.testing.expectEqual(sidecarCount(cell), retained);
            }
        }
    }

    try screen.resize(std.testing.allocator, 4, 4);
    try std.testing.expect(!containsCodepoint(&screen, 0x754c));
    try std.testing.expect(!containsCodepoint(&screen, 0x8a9e));
}

test "one-column omission releases every failed prepared resize candidate" {
    const backing_bytes = try std.testing.allocator.alloc(
        u8,
        Screen.retained_output_bytes_max * 4,
    );
    defer std.testing.allocator.free(backing_bytes);
    var deterministic = std.heap.FixedBufferAllocator.init(backing_bytes);
    try std.testing.checkAllAllocationFailures(
        deterministic.allocator(),
        oneColumnOmissionAllocation,
        .{},
    );
}

fn oneColumnOmissionAllocation(allocator: std.mem.Allocator) !void {
    var screen = try oneColumnOmissionFixture();
    defer screen.deinit(std.testing.allocator);
    const cells_before = try std.testing.allocator.dupe(ScreenCell, screen.cells.?);
    defer std.testing.allocator.free(cells_before);
    const ranges_before = try std.testing.allocator.dupe(
        scalar_storage.Range,
        screen.scalars.?.ranges,
    );
    defer std.testing.allocator.free(ranges_before);
    const pages_before = try std.testing.allocator.dupe(
        u8,
        std.mem.sliceAsBytes(screen.scalars.?.pages),
    );
    defer std.testing.allocator.free(pages_before);
    const cursor_before = screen.cursor;
    const history_count_before = screen.history_count;

    var candidate = screen.prepareResize(allocator, 4, 1) catch |err| {
        try std.testing.expectEqualSlices(ScreenCell, cells_before, screen.cells.?);
        try std.testing.expectEqualSlices(
            scalar_storage.Range,
            ranges_before,
            screen.scalars.?.ranges,
        );
        try std.testing.expectEqualSlices(
            u8,
            pages_before,
            std.mem.sliceAsBytes(screen.scalars.?.pages),
        );
        try std.testing.expectEqualDeep(cursor_before, screen.cursor);
        try std.testing.expectEqual(history_count_before, screen.history_count);
        return err;
    };
    candidate.deinit(allocator);
}

fn oneColumnOmissionFixture() !Screen {
    var screen = try Screen.initWithCellsAndHistory(
        std.testing.allocator,
        2,
        4,
        4,
    );
    errdefer screen.deinit(std.testing.allocator);
    screen.writeCell(0x8a9e);
    screen.writeCell('H');
    screen.cursor.setColByClient(0);
    screen.lineFeed();
    screen.lineFeed();
    screen.writeCell('A');
    screen.writeCell(0x754c);
    var scalar: u21 = 0x0300;
    while (scalar < 0x0300 + 23) : (scalar += 1)
        screen.writeCell(scalar);
    screen.writeCell('B');
    return screen;
}

fn copyProjectedHistory(
    allocator: std.mem.Allocator,
    screen: *const Screen,
) std.mem.Allocator.Error![]ScreenCell {
    const cell_count = @as(usize, screen.history_count) * screen.cols;
    const result = try allocator.alloc(ScreenCell, cell_count);
    var logical_row: u32 = 0;
    while (logical_row < screen.history_count) : (logical_row += 1) {
        const slot = screen.historySlotForLogicalRow(logical_row) orelse unreachable;
        const source = slot * @as(u32, screen.cols);
        const destination = @as(usize, logical_row) * screen.cols;
        @memcpy(
            result[destination..][0..screen.cols],
            screen.history.?[@intCast(source)..@intCast(source + screen.cols)],
        );
    }
    return result;
}

fn containsCodepoint(screen: *const Screen, codepoint: u32) bool {
    for (screen.cells orelse &.{}) |cell|
        if (cell.codepoint == codepoint) return true;
    var logical_row: u32 = 0;
    while (logical_row < screen.history_count) : (logical_row += 1) {
        const slot = screen.historySlotForLogicalRow(logical_row) orelse unreachable;
        const base = slot * @as(u32, screen.cols);
        for (screen.history.?[@intCast(base)..@intCast(base + screen.cols)]) |cell|
            if (cell.codepoint == codepoint) return true;
    }
    return false;
}

test "Unicode scalar pressure preserves wide occupancy and terminal state" {
    var screen = try Screen.initWithCells(std.testing.allocator, 1, 3);
    defer screen.deinit(std.testing.allocator);
    screen.writeCell(0x754c);
    var scalar_value: u21 = 0x0300;
    while (scalar_value < 0x0300 + 23) : (scalar_value += 1)
        screen.writeCell(scalar_value);

    const cells_before = try std.testing.allocator.dupe(
        ScreenCell,
        screen.cells.?,
    );
    defer std.testing.allocator.free(cells_before);
    const cursor_before = screen.cursor;
    const wrap_before = screen.wrap_pending;
    const graphic_before = screen.last_graphic;
    const ranges_before = try std.testing.allocator.dupe(
        scalar_storage.Range,
        screen.scalars.?.ranges,
    );
    defer std.testing.allocator.free(ranges_before);
    const pages_before = try std.testing.allocator.dupe(
        u8,
        std.mem.sliceAsBytes(screen.scalars.?.pages),
    );
    defer std.testing.allocator.free(pages_before);

    screen.writeCell(0x0317);
    try std.testing.expectEqualSlices(ScreenCell, cells_before, screen.cells.?);
    try std.testing.expectEqualDeep(cursor_before, screen.cursor);
    try std.testing.expectEqual(wrap_before, screen.wrap_pending);
    try std.testing.expectEqualDeep(graphic_before, screen.last_graphic);
    try std.testing.expectEqualSlices(
        scalar_storage.Range,
        ranges_before,
        screen.scalars.?.ranges,
    );
    try std.testing.expectEqualSlices(
        u8,
        pages_before,
        std.mem.sliceAsBytes(screen.scalars.?.pages),
    );
}

test "REP reports no preceding graphic separately from scalar pressure" {
    var empty = try Screen.initWithCells(std.testing.allocator, 1, 1);
    defer empty.deinit(std.testing.allocator);
    try std.testing.expect(!empty.repeatPreceding(1));
    try std.testing.expect(empty.last_graphic == null);

    const cols: u16 = 102;
    var pressured = try Screen.initWithCells(
        std.testing.allocator,
        1,
        cols,
    );
    defer pressured.deinit(std.testing.allocator);
    pressured.writeCell('a');
    var scalar_value: u21 = 0x0300;
    while (scalar_value < 0x0300 + 23) : (scalar_value += 1)
        pressured.writeCell(scalar_value);
    try std.testing.expect(pressured.last_graphic != null);

    var tail: [scalar_storage.maximum_tail_scalars]u32 = undefined;
    for (&tail, 0..) |*scalar, index|
        scalar.* = 0x0400 + @as(u32, @intCast(index));
    var cell: usize = 1;
    while (cell < cols) : (cell += 1) {
        try pressured.scalars.?.set(cell, 0, &tail);
        pressured.cells.?[cell] = .{
            .codepoint = 'b',
            .combining_len = scalar_storage.maximum_scalars - 1,
            .combining = .{ 0x0400, 0x0401, 0x0402 },
            .attrs = initial_cell_attrs,
        };
    }

    const cells_before = try std.testing.allocator.dupe(
        ScreenCell,
        pressured.cells.?,
    );
    defer std.testing.allocator.free(cells_before);
    const ranges_before = try std.testing.allocator.dupe(
        scalar_storage.Range,
        pressured.scalars.?.ranges,
    );
    defer std.testing.allocator.free(ranges_before);
    const pages_before = try std.testing.allocator.dupe(
        u8,
        std.mem.sliceAsBytes(pressured.scalars.?.pages),
    );
    defer std.testing.allocator.free(pages_before);
    const cursor_before = pressured.cursor;
    const wrap_before = pressured.wrap_pending;
    const graphic_before = pressured.last_graphic;
    try std.testing.expect(!pressured.repeatPreceding(1));
    try std.testing.expectEqualSlices(ScreenCell, cells_before, pressured.cells.?);
    try std.testing.expectEqualSlices(
        scalar_storage.Range,
        ranges_before,
        pressured.scalars.?.ranges,
    );
    try std.testing.expectEqualSlices(
        u8,
        pages_before,
        std.mem.sliceAsBytes(pressured.scalars.?.pages),
    );
    try std.testing.expectEqualDeep(cursor_before, pressured.cursor);
    try std.testing.expectEqual(wrap_before, pressured.wrap_pending);
    try std.testing.expectEqualDeep(graphic_before, pressured.last_graphic);
}

test "first projected admission ignores untouched future slots" {
    const backing = try std.heap.page_allocator.alloc(u8, 3 * 1024 * 1024);
    defer std.heap.page_allocator.free(backing);
    @memset(backing, 0xa5);
    var fixed = std.heap.FixedBufferAllocator.init(backing);
    const allocator = fixed.allocator();

    var screen = try Screen.initWithCellsAndHistory(allocator, 2, 2, 4);
    defer screen.deinit(allocator);
    var cell = blank_cell;
    cell.codepoint = 'P';
    screen.cells.?[@intCast(screen.rowStart(0))] = cell;

    screen.storeHistoryRow(0);
    try std.testing.expectEqual(@as(u64, 0), screen.history_loss_generation);
    try std.testing.expectEqual(@as(u32, 1), screen.history_count);
    try std.testing.expectEqual(@as(u21, 'P'), screen.historyRowAt(0, 0));
}

test "inline combining history remains entirely in fixed projected storage" {
    var screen = try Screen.initWithCellsAndHistory(
        std.testing.allocator,
        2,
        4,
        4,
    );
    defer screen.deinit(std.testing.allocator);

    var inline_cell = blank_cell;
    inline_cell.codepoint = 'a';
    inline_cell.combining_len = scalar_storage.inline_scalars - 1;
    inline_cell.combining = .{ 0x0300, 0x0301, 0x0302 };
    screen.cells.?[@intCast(screen.rowStart(0))] = inline_cell;

    screen.storeHistoryRow(0);
    try std.testing.expectEqual(@as(u32, 1), screen.history_count);
    try std.testing.expectEqualDeep(inline_cell, screen.historyCellAt(0, 0));
    const slot = screen.historySlotForRecency(0).?;
    const projected_index = slot * @as(u32, screen.cols);
    try std.testing.expectEqual(
        @as(usize, 0),
        (try screen.history_scalars.?.tail(
            projected_index,
            inline_cell.combining_len,
        )).len,
    );

    screen.clearRowRange(0, 0, screen.cols);
    try std.testing.expect(screen.scrollDownFromHistory(1));
    try std.testing.expectEqual(@as(u32, 0), screen.history_count);
    try std.testing.expectEqualDeep(inline_cell, screen.cellInfoAt(0, 0));
}

test "twenty four scalars cross projected history and reflow page boundaries" {
    const old_cols: u16 = scalar_storage.page_cells + 1;
    var screen = try Screen.initWithCellsAndHistory(
        std.testing.allocator,
        2,
        old_cols,
        4,
    );
    defer screen.deinit(std.testing.allocator);

    const lead: usize = scalar_storage.page_cells - 1;
    var cell_value = blank_cell;
    cell_value.codepoint = 'a';
    cell_value.combining_len = scalar_storage.maximum_scalars - 1;
    cell_value.combining = .{ 0x0300, 0x0301, 0x0302 };
    var tail: [scalar_storage.maximum_tail_scalars]u32 = undefined;
    for (&tail, 0..) |*scalar, index| scalar.* = 0x0303 + @as(u32, @intCast(index));
    try screen.scalars.?.set(lead, 0, &tail);
    screen.cells.?[lead] = cell_value;

    screen.storeHistoryRow(0);
    try std.testing.expectEqual(@as(u32, 1), screen.history_count);
    const projected_slot = screen.historySlotForRecency(0).?;
    const projected_lead = projected_slot * @as(u32, old_cols) + lead;
    try std.testing.expectEqualSlices(
        u32,
        &tail,
        try screen.history_scalars.?.tail(
            projected_lead,
            cell_value.combining_len,
        ),
    );
    screen.clearRowRange(0, 0, old_cols);
    try std.testing.expect(screen.scrollDownFromHistory(1));
    const restored_lead = screen.rowStart(0) + @as(u32, @intCast(lead));
    try std.testing.expectEqualSlices(
        u32,
        &tail,
        try screen.scalars.?.tail(restored_lead, cell_value.combining_len),
    );
    try std.testing.expectEqual(@as(u32, 0), screen.history_count);

    try screen.resize(std.testing.allocator, 3, 2048);
    var found: ?usize = null;
    for (screen.cells.?, 0..) |cell, index| {
        if (cell.codepoint == 'a') {
            found = index;
            break;
        }
    }
    const resized_lead = found orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualSlices(
        u32,
        &tail,
        try screen.scalars.?.tail(
            resized_lead,
            screen.cells.?[resized_lead].combining_len,
        ),
    );
}

test "projected history scalar pressure preserves accepted ownership and later reuses it" {
    const cols: u16 = 102;
    var screen = try Screen.initWithCellsAndHistory(
        std.testing.allocator,
        2,
        cols,
        2,
    );
    defer screen.deinit(std.testing.allocator);
    var tail: [scalar_storage.maximum_tail_scalars]u32 = undefined;
    for (&tail, 0..) |*scalar, index| scalar.* = 0x0400 + @as(u32, @intCast(index));
    const second_row = screen.rowStart(1);

    // Keep the oldest slot scalar-free. The newer slot consumes all but eight
    // external scalar slots in the fixed projected-history page.
    var light = blank_cell;
    light.codepoint = 'x';
    screen.cells.?[second_row] = light;
    screen.storeHistoryRow(1);

    screen.clearRowRange(1, 0, cols);
    var col: usize = 0;
    while (col < cols) : (col += 1) {
        var value = blank_cell;
        value.codepoint = 'b';
        value.combining_len = scalar_storage.maximum_scalars - 2;
        value.combining = .{ 0x0310, 0x0311, 0x0312 };
        try screen.scalars.?.set(second_row + col, 0, tail[0..19]);
        screen.cells.?[second_row + col] = value;
    }
    screen.storeHistoryRow(1);
    try std.testing.expectEqual(@as(u64, 0), screen.history_loss_generation);
    try std.testing.expectEqual(@as(u32, screen.history_capacity), screen.history_count);

    // Replacing the scalar-free oldest row now needs six complete tails, but
    // the retained newer row leaves only eight scalar slots. Preflight must
    // fail without evicting or partially mutating accepted projected state.
    screen.clearRowRange(1, 0, cols);
    col = 0;
    while (col < 6) : (col += 1) {
        var value = blank_cell;
        value.codepoint = 'c';
        value.combining_len = scalar_storage.maximum_scalars - 1;
        value.combining = .{ 0x0320, 0x0321, 0x0322 };
        try screen.scalars.?.set(second_row + col, 0, &tail);
        screen.cells.?[second_row + col] = value;
    }

    const before_ranges = try std.testing.allocator.dupe(
        scalar_storage.Range,
        screen.history_scalars.?.ranges,
    );
    defer std.testing.allocator.free(before_ranges);
    const before_pages = try std.testing.allocator.dupe(
        u8,
        std.mem.sliceAsBytes(screen.history_scalars.?.pages),
    );
    defer std.testing.allocator.free(before_pages);
    const before_cells = try copyProjectedHistory(std.testing.allocator, &screen);
    defer std.testing.allocator.free(before_cells);
    const before_flags = try std.testing.allocator.dupe(u8, screen.history_flags.?);
    defer std.testing.allocator.free(before_flags);
    const before_history_count = screen.history_count;
    const before_history_write_idx = screen.history_write_idx;
    const before_history_row_base = screen.history_row_base;
    const before_boundary_stored = screen.history_boundary_stored;
    const before_boundary_total = screen.history_boundary_total;
    const before_boundary_active = screen.history_boundary_active;

    screen.storeHistoryRow(1);
    try std.testing.expectEqual(@as(u64, 1), screen.history_loss_generation);
    try std.testing.expectEqualSlices(
        scalar_storage.Range,
        before_ranges,
        screen.history_scalars.?.ranges,
    );
    try std.testing.expectEqualSlices(
        u8,
        before_pages,
        std.mem.sliceAsBytes(screen.history_scalars.?.pages),
    );
    const after_cells = try copyProjectedHistory(std.testing.allocator, &screen);
    defer std.testing.allocator.free(after_cells);
    try std.testing.expectEqualSlices(ScreenCell, before_cells, after_cells);
    try std.testing.expectEqualSlices(u8, before_flags, screen.history_flags.?);
    try std.testing.expectEqual(before_history_count, screen.history_count);
    try std.testing.expectEqual(before_history_write_idx, screen.history_write_idx);
    try std.testing.expectEqual(before_history_row_base, screen.history_row_base);
    try std.testing.expectEqual(before_boundary_stored, screen.history_boundary_stored);
    try std.testing.expectEqual(before_boundary_total, screen.history_boundary_total);
    try std.testing.expectEqual(before_boundary_active, screen.history_boundary_active);

    try std.testing.expect(screen.clearScrollback());
    screen.storeHistoryRow(1);
    try std.testing.expectEqual(@as(u32, 1), screen.history_count);
    try std.testing.expectEqual(@as(u64, 1), screen.history_loss_generation);
}

// =============================================================================
// Color and cursor value types
// =============================================================================

// Stores one exact 24-bit terminal color.
const ScreenRgb = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,
};

/// Classifies one terminal color independently from its internal storage.
pub const ScreenColorKind = enum(u8) {
    default,
    indexed,
    rgb,
};

const Kind = ScreenColorKind;

// Stores a default, indexed, or RGB terminal color.
const ScreenColor = struct {
    kind: Kind,
    value: u32,

    /// Returns the semantic terminal-color class.
    pub fn colorKind(self: ScreenColor) ScreenColorKind {
        return self.kind;
    }

    /// Returns zero for default, palette index for indexed, or 0xRRGGBB for RGB.
    pub fn colorValue(self: ScreenColor) u32 {
        return self.value;
    }

    /// Constructs an indexed terminal color.
    pub fn indexed(idx: u8) ScreenColor {
        return .{ .kind = .indexed, .value = idx };
    }

    /// Constructs an exact RGB terminal color.
    pub fn rgb(rgb_value: ScreenRgb) ScreenColor {
        return .{
            .kind = .rgb,
            .value = (@as(u32, rgb_value.r) << 16) | (@as(u32, rgb_value.g) << 8) | @as(u32, rgb_value.b),
        };
    }

    /// Returns RGB components only when this color is RGB.
    pub fn rgbComponents(r: u8, g: u8, b: u8) ScreenColor {
        return rgb(.{ .r = r, .g = g, .b = b });
    }

    /// Resolves this cell color against one complete terminal palette and
    /// caller-selected default without retaining either borrowed value.
    pub fn resolve(self: ScreenColor, default_value: ScreenRgb, palette: *const [256]ScreenRgb) ScreenRgb {
        return switch (self.kind) {
            .default => default_value,
            .indexed => palette[@as(u8, @intCast(self.value))],
            .rgb => .{
                .r = @truncate(self.value >> 16),
                .g = @truncate(self.value >> 8),
                .b = @truncate(self.value),
            },
        };
    }
};

// Provides the immutable default foreground color.
const default_cell_foreground = ScreenColor{ .kind = .default, .value = 0 };
// Provides the immutable default background color.
const default_cell_background = ScreenColor{ .kind = .default, .value = 0 };
// Provides the immutable default underline color.
const default_cell_underline_color = ScreenColor{ .kind = .default, .value = 0 };

/// Identifies block, underline, bar, or hidden cursor presentation.
pub const ScreenCursorShape = enum {
    block,
    underline,
    bar,
    none,
};

// Stores cursor shape and blink state.
const ScreenCursorStyle = struct {
    shape: ScreenCursorShape,
    blink: bool,
};

/// Selects a program override or restoration to configured default style.
pub const CursorStyleCommand = union(enum) {
    restore_default,
    program_override: ScreenCursorStyle,
};

// Provides the default blinking block cursor.
const initial_cursor_style = ScreenCursorStyle{ .shape = .block, .blink = true };

// Owns cursor position, style layers, and client-movement identity.
const ScreenSemanticCursor = struct {
    row: u16,
    col: u16,
    visible: bool,
    effective_shape: ScreenCursorShape,
    blink_intent: bool,
    default_style: ScreenCursorStyle,
    program_override_style: ?ScreenCursorStyle,
    cursor_color: ?ScreenRgb,
    cursor_text_color: ?ScreenRgb,
    position_changed_by_client_at: u64,
    /// Monotonic timestamp captured when the latest absolute-position command parsed.
    position_changed_timestamp_ns: u64,
    /// Timestamp supplied for the current parser turn; consumed by an
    /// absolute-position command and ignored by structural movement.
    movement_timestamp_ns: u64,

    /// Initializes a cursor at the origin with the supplied default style.
    pub fn init(default_style: ScreenCursorStyle) ScreenSemanticCursor {
        return .{
            .row = 0,
            .col = 0,
            .visible = true,
            .effective_shape = default_style.shape,
            .blink_intent = default_style.blink,
            .default_style = default_style,
            .program_override_style = null,
            .cursor_color = null,
            .cursor_text_color = null,
            .position_changed_by_client_at = 0,
            .position_changed_timestamp_ns = 0,
            .movement_timestamp_ns = 0,
        };
    }

    /// Returns position and style to terminal-reset defaults and advances client identity.
    pub fn reset(self: *ScreenSemanticCursor) void {
        const default_style = self.default_style;
        const movement_timestamp_ns = self.movement_timestamp_ns;
        self.* = init(default_style);
        self.movement_timestamp_ns = movement_timestamp_ns;
    }

    /// Returns the cursor position and style to the alternate-screen origin;
    /// the enclosing Screen owns pending-wrap reset.
    fn resetForAltEntry(self: *ScreenSemanticCursor) void {
        self.row = 0;
        self.col = 0;
        // Alternate-screen entry clears the program override, matching Kitty's
        // NO_CURSOR_SHAPE sentinel while retaining the configured default for
        // the next visible cursor publication.
        self.effective_shape = self.default_style.shape;
        self.blink_intent = self.default_style.blink;
        self.program_override_style = null;
        self.position_changed_by_client_at = 0;
        self.position_changed_timestamp_ns = 0;
    }

    /// Returns the program override when present, otherwise the configured default.
    pub fn effectiveStyle(self: *const ScreenSemanticCursor) ScreenCursorStyle {
        return .{ .shape = self.effective_shape, .blink = self.blink_intent };
    }

    /// Replaces the configured default without disturbing a program override.
    pub fn setDefaultStyle(self: *ScreenSemanticCursor, style: ScreenCursorStyle) void {
        self.default_style = style;
        if (self.program_override_style == null) self.applyStyle(style);
    }

    /// Installs a program cursor-style override.
    pub fn setProgramStyle(self: *ScreenSemanticCursor, style: ScreenCursorStyle) void {
        self.program_override_style = style;
        self.applyStyle(style);
    }

    /// Replaces only the program-selected shape while preserving blink intent.
    fn setProgramShape(self: *ScreenSemanticCursor, shape: ScreenCursorShape) void {
        self.setProgramStyle(.{ .shape = shape, .blink = self.blink_intent });
    }

    // Replaces blink intent while preserving the active shape and style layer.
    /// Selects effective cursor blinking and reports semantic change.
    pub fn setBlink(self: *ScreenSemanticCursor, enabled: bool) bool {
        if (self.blink_intent == enabled) return false;
        self.blink_intent = enabled;
        if (self.program_override_style) |*style| style.blink = enabled;
        return true;
    }

    /// Restores a previously saved effective style as the program override.
    pub fn restoreSavedStyle(self: *ScreenSemanticCursor, style: ScreenCursorStyle) void {
        self.program_override_style = if (style.shape == self.default_style.shape and
            style.blink == self.default_style.blink)
            null
        else
            style;
        self.applyStyle(style);
    }

    /// Clears the program override and exposes the configured default.
    pub fn restoreDefaultStyle(self: *ScreenSemanticCursor) void {
        self.program_override_style = null;
        self.applyStyle(self.default_style);
    }

    /// Moves to exact bounded coordinates and advances client-movement identity.
    pub fn setPositionByClient(self: *ScreenSemanticCursor, row: u16, col: u16) void {
        if (self.row != row or self.col != col) self.position_changed_by_client_at +|= 1;
        self.row = row;
        self.col = col;
    }

    /// Supplies the monotonic VT parse timestamp available to the next
    /// absolute-position command. Structural movement never consumes it.
    pub fn setMovementTimestamp(self: *ScreenSemanticCursor, timestamp_ns: u64) void {
        self.movement_timestamp_ns = timestamp_ns;
    }

    /// Records Kitty's absolute-position command timestamp even when the
    /// resulting coordinates are unchanged.
    pub fn markAbsolutePositionTimestamp(self: *ScreenSemanticCursor) void {
        self.position_changed_timestamp_ns = self.movement_timestamp_ns;
    }

    /// Moves to exact bounded coordinates without changing client identity.
    pub fn setPositionStructural(self: *ScreenSemanticCursor, row: u16, col: u16) void {
        self.row = row;
        self.col = col;
    }

    /// Moves the row and advances client-movement identity.
    pub fn setRowByClient(self: *ScreenSemanticCursor, row: u16) void {
        self.setPositionByClient(row, self.col);
    }

    /// Moves the column and advances client-movement identity.
    pub fn setColByClient(self: *ScreenSemanticCursor, col: u16) void {
        self.setPositionByClient(self.row, col);
    }

    fn applyStyle(self: *ScreenSemanticCursor, style: ScreenCursorStyle) void {
        self.effective_shape = style.shape;
        self.blink_intent = style.blink;
    }
};

/// Erase extent selected by CSI display and line erase controls.
pub const ScreenEraseMode = enum(u2) {
    cursor_to_end = 0,
    start_to_cursor = 1,
    all = 2,
    scrollback = 3,
};

// =============================================================================
// Resize and reflow engine
// =============================================================================

// Convert a checked standard-library length to the history/reflow domain.
fn screenCount32(len: usize) u32 {
    std.debug.assert(len <= std.math.maxInt(u32));
    return @intCast(len);
}

// Return rows needed for `cell_count`, or zero when no columns exist.
fn rowCountForCells(cell_count: u32, cols: u16) u32 {
    if (cols == 0) return 0;
    return @max(@as(u32, 1), std.math.divCeil(u32, cell_count, cols) catch unreachable);
}

// Owned logical terminal line used while reflowing retained content.
const LogicalLine = struct {
    cells: std.ArrayListUnmanaged(ScreenCell) = .empty,
    scalars: ?scalar_storage.Storage = null,
    cursor_offset: ?u32 = null,

    /// Release cloned cells and reset the line.
    fn deinit(self: *LogicalLine, allocator: std.mem.Allocator) void {
        if (self.scalars) |*storage| storage.deinit();
        self.cells.deinit(allocator);
        self.* = .{};
    }
};

/// Owned logical-content snapshot and cursor location used by resize.
const LogicalSnapshot = struct {
    logical_lines: std.ArrayListUnmanaged(LogicalLine) = .empty,
    cursor_found: bool = false,
    cursor_line_index: u32 = 0,
    cursor_offset: u32 = 0,

    /// Release every cloned line and reset the snapshot.
    fn deinit(self: *LogicalSnapshot, allocator: std.mem.Allocator) void {
        for (self.logical_lines.items) |*line| line.deinit(allocator);
        self.logical_lines.deinit(allocator);
        self.* = .{};
    }
};

/// Identifies why one finalized logical-output line could not be retained.
pub const OutputLossReason = enum { line_too_long };

const OutputLoss = struct {
    byte_count: usize,
    reason: OutputLossReason,
};

const OutputText = struct {
    start: u32,
    len: u32,

    /// Borrows the ordered physical slices backing one circular text range.
    pub fn slices(self: OutputText, storage: []const u8) [2][]const u8 {
        std.debug.assert(storage.len == Screen.retained_output_bytes_max);
        std.debug.assert(self.start < storage.len);
        std.debug.assert(self.len <= storage.len);
        const start: usize = self.start;
        const len: usize = self.len;
        const first_len = @min(len, storage.len - start);
        return .{
            storage[start..][0..first_len],
            storage[0 .. len - first_len],
        };
    }
};

// Owns one bounded finalized primary-screen result and its stable identity.
const OutputLine = struct {
    const Value = union(enum) {
        text: OutputText,
        loss: OutputLoss,

        fn retainedBytes(self: Value) usize {
            return switch (self) {
                .text => |text| text.len,
                .loss => 0,
            };
        }
    };

    const empty: OutputLine = .{
        .id = 0,
        .value = .{ .loss = .{
            .byte_count = 0,
            .reason = .line_too_long,
        } },
    };

    id: u64,
    value: Value,
};

// Borrows one row range from a reflowed logical line.
const RewrappedRow = struct {
    start: u32,
    len: u16,
    wrapped: bool,
    geometry: Screen.LineGeometry = .single_width,
};

// Finds the logical line containing a projected row within parallel bounded arrays.
fn firstLineForRowBounded(line_row_starts: []const u32, line_row_counts: []const u16, row_index: u32) ?u32 {
    std.debug.assert(line_row_starts.len == line_row_counts.len);
    for (line_row_starts, line_row_counts, 0..) |row_start, row_count, line_idx| {
        if (row_count == 0) continue;
        if (row_index < row_start + row_count) return @intCast(line_idx);
    }
    return null;
}

/// Zero-based rectangular area whose optional lower bounds extend to the page edge.
pub const RectArea = struct {
    top: u16,
    left: u16,
    bottom: ?u16,
    right: ?u16,
};

/// Page-qualified rectangular copy request.
pub const RectCopy = struct {
    area: RectArea,
    source_page: u16,
    dest_top: u16,
    dest_left: u16,
    dest_page: u16,
};

/// Owned reflow rows, line projections, and projected cursor state.
const ReflowState = struct {
    flat_rows: std.ArrayListUnmanaged(ScreenCell) = .empty,
    scalars: ?scalar_storage.Storage = null,
    rewrapped: std.ArrayListUnmanaged(RewrappedRow) = .empty,
    line_row_starts: std.ArrayListUnmanaged(u32) = .empty,
    line_row_counts: std.ArrayListUnmanaged(u16) = .empty,
    global_cursor_row: u32 = 0,
    global_cursor_col: u16 = 0,
    next_wrap_pending: bool = false,

    /// Release every reflow allocation and reset the value.
    fn deinit(self: *ReflowState, allocator: std.mem.Allocator) void {
        self.flat_rows.deinit(allocator);
        if (self.scalars) |*storage| storage.deinit();
        self.rewrapped.deinit(allocator);
        self.line_row_starts.deinit(allocator);
        self.line_row_counts.deinit(allocator);
        self.* = .{};
    }
};

const ReflowError = std.mem.Allocator.Error || error{ScalarCapacity};

// Derived projection range into complete reflow output.
const ResizeProjection = struct {
    total_rows: u32,
    visible_rows_kept: u16,
    visible_start: u32,
    first_visible_line: u32,
    hidden_rows_in_first_visible_line: u16,
};

/// Owned visible-grid buffers transferred together into a replacement Screen.
const ResizeBuffers = struct {
    cells: ?[]ScreenCell,
    scalars: ?scalar_storage.Storage,
    row_flags: ?[]u8,
    tab_stops: tab_stops_mod.State,

    const empty: ResizeBuffers = .{
        .cells = null,
        .scalars = null,
        .row_flags = null,
        .tab_stops = .empty,
    };

    /// Release every owned buffer and reset the value.
    fn deinit(self: *ResizeBuffers, allocator: std.mem.Allocator) void {
        if (self.cells) |buf| allocator.free(buf);
        if (self.scalars) |*storage| storage.deinit();
        if (self.row_flags) |buf| allocator.free(buf);
        self.tab_stops.deinit(allocator);
        self.* = empty;
    }

    /// Transfer all buffers to one owner and leave this value empty.
    fn take(self: *ResizeBuffers) ResizeBuffers {
        const owned = self.*;
        self.* = empty;
        return owned;
    }
};

/// Reflow one borrowed logical snapshot to allocator-owned rows without consuming it.
///
/// Allocation failure releases partial output and leaves the snapshot reusable.
fn reflowLogicalLines(
    allocator: std.mem.Allocator,
    lines: LogicalSnapshot,
    cols: u16,
) ReflowError!ReflowState {
    var result = ReflowState{};
    errdefer result.deinit(allocator);

    var total_rows: usize = 0;
    for (lines.logical_lines.items) |line| {
        const rows = rowCountForSemanticCells(line.cells.items, cols);
        total_rows = std.math.add(usize, total_rows, rows) catch
            return error.OutOfMemory;
    }
    const total_cells = std.math.mul(usize, total_rows, cols) catch
        return error.OutOfMemory;
    if (total_cells > 0) {
        result.scalars = scalar_storage.Storage.init(
            allocator,
            total_cells,
        ) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCapacity => return error.OutOfMemory,
        };
    }

    var row_cursor_base: u32 = 0;
    for (lines.logical_lines.items, 0..) |line, line_idx| {
        const rewrapped_before = result.rewrapped.items.len;
        const has_cursor = lines.cursor_found and lines.cursor_line_index == line_idx;
        const line_cursor_offset = boundedCursorOffset(line, has_cursor, lines.cursor_offset);
        const row_count: u16 = @intCast(
            rowCountForSemanticCells(line.cells.items, cols),
        );
        try result.line_row_starts.append(allocator, @intCast(result.rewrapped.items.len));
        try result.line_row_counts.append(allocator, row_count);
        updateSemanticCursor(
            &result,
            row_cursor_base,
            line.cells.items,
            line_cursor_offset,
            cols,
            has_cursor,
        );
        try appendRewrappedRows(allocator, &result, line, row_count, cols);
        row_cursor_base += row_count;

        std.debug.assert(result.line_row_starts.items.len == result.line_row_counts.items.len);
        std.debug.assert(result.rewrapped.items.len == rewrapped_before + row_count);
        std.debug.assert(result.rewrapped.items.len == row_cursor_base);
        std.debug.assert(result.flat_rows.items.len == result.rewrapped.items.len * screenResizeColCount(cols));
    }

    std.debug.assert(result.line_row_starts.items.len == lines.logical_lines.items.len);
    std.debug.assert(result.line_row_counts.items.len == lines.logical_lines.items.len);
    return result;
}

fn appendRewrappedRows(
    allocator: std.mem.Allocator,
    result: *ReflowState,
    line: LogicalLine,
    row_count: u16,
    cols: u16,
) ReflowError!void {
    if (cols == 0) return;
    if (row_count == 0) unreachable;

    const flat_rows_before = screenCount32(result.flat_rows.items.len);
    const rewrapped_before = result.rewrapped.items.len;
    var row_idx: u16 = 0;
    while (row_idx < row_count) : (row_idx += 1) {
        try result.rewrapped.append(allocator, .{
            .start = screenCount32(result.flat_rows.items.len),
            .len = 0,
            .wrapped = row_idx + 1 < row_count,
        });
        try appendBlankRow(allocator, &result.flat_rows, cols);
    }

    var source_index: usize = 0;
    var destination_row: usize = 0;
    var destination_col: u16 = 0;
    while (source_index < line.cells.items.len) {
        const cell = line.cells.items[source_index];
        if (isSemanticWideCell(cell) and isCellContinuation(cell)) {
            source_index += 1;
            continue;
        }
        const span: u16 = if (isSemanticWideLead(cell)) cell.width else 1;
        if (span > cols) {
            std.debug.assert(source_index + span <= line.cells.items.len);
            source_index += span;
            continue;
        }
        if (destination_col + span > cols) {
            destination_row += 1;
            destination_col = 0;
        }
        std.debug.assert(destination_row < row_count);
        const destination =
            @as(usize, flat_rows_before) +
            destination_row * @as(usize, cols) +
            destination_col;
        result.flat_rows.items[destination] = cell;
        if (span == 2) {
            std.debug.assert(source_index + 1 < line.cells.items.len);
            const continuation = line.cells.items[source_index + 1];
            std.debug.assert(
                isSemanticWideCell(continuation) and
                    isCellContinuation(continuation),
            );
            result.flat_rows.items[destination + 1] = continuation;
        }
        if (sidecarCount(cell) != 0) {
            copyScalarCells(
                if (line.scalars) |*storage|
                    storage
                else
                    @panic("accepted logical scalar owner missing"),
                line.cells.items[source_index..][0..1],
                @intCast(source_index),
                &result.scalars.?,
                destination,
                1,
            ) catch |err| switch (err) {
                error.ScalarCapacity => return error.ScalarCapacity,
                error.InvalidRange => @panic("accepted logical scalar mismatch"),
            };
        }
        destination_col += span;
        result.rewrapped.items[rewrapped_before + destination_row].len =
            destination_col;
        source_index += span;
    }

    std.debug.assert(
        screenCount32(result.flat_rows.items.len) ==
            flat_rows_before + @as(u32, row_count) * screenResizeColCount(cols),
    );
}

fn appendBlankRow(
    allocator: std.mem.Allocator,
    flat_rows: *std.ArrayListUnmanaged(ScreenCell),
    cols: u16,
) std.mem.Allocator.Error!void {
    var col_idx: u16 = 0;
    while (col_idx < cols) : (col_idx += 1)
        try flat_rows.append(allocator, blank_cell);
}

fn updateSemanticCursor(
    result: *ReflowState,
    row_cursor_base: u32,
    cells: []const ScreenCell,
    line_cursor_offset: u32,
    cols: u16,
    has_cursor: bool,
) void {
    if (!has_cursor) return;
    if (cols == 0) {
        result.global_cursor_row = 0;
        result.global_cursor_col = 0;
        result.next_wrap_pending = false;
        return;
    }

    var source_index: u32 = 0;
    var row: u32 = 0;
    var col: u16 = 0;
    while (source_index < line_cursor_offset and source_index < cells.len) {
        const cell = cells[source_index];
        if (isSemanticWideCell(cell) and isCellContinuation(cell)) {
            source_index += 1;
            continue;
        }
        const span: u16 = if (isSemanticWideLead(cell)) cell.width else 1;
        if (span > cols) {
            const span_end = source_index + span;
            if (line_cursor_offset <= span_end) {
                source_index = line_cursor_offset;
                break;
            }
            source_index = span_end;
            continue;
        }
        if (col + span > cols) {
            row += 1;
            col = 0;
        }
        const remaining = line_cursor_offset - source_index;
        if (remaining < span) {
            col += @intCast(remaining);
            source_index = line_cursor_offset;
            break;
        }
        col += span;
        source_index += span;
        if (col == cols and source_index < line_cursor_offset) {
            row += 1;
            col = 0;
        }
    }
    if (col == cols) {
        result.global_cursor_row = row_cursor_base + row;
        result.global_cursor_col = cols - 1;
        result.next_wrap_pending = true;
    } else {
        result.global_cursor_row = row_cursor_base + row;
        result.global_cursor_col = col;
        result.next_wrap_pending = false;
    }
}

fn rowCountForSemanticCells(cells: []const ScreenCell, cols: u16) u32 {
    if (cols == 0) return 0;
    if (cells.len == 0) return 1;
    var rows: u32 = 1;
    var col: u16 = 0;
    var index: usize = 0;
    while (index < cells.len) {
        const cell = cells[index];
        if (isSemanticWideCell(cell) and isCellContinuation(cell)) {
            index += 1;
            continue;
        }
        const span: u16 = if (isSemanticWideLead(cell)) cell.width else 1;
        if (span > cols) {
            std.debug.assert(index + span <= cells.len);
            index += span;
            continue;
        }
        if (col + span > cols) {
            rows += 1;
            col = 0;
        }
        col += span;
        index += span;
        if (col == cols and index < cells.len) {
            rows += 1;
            col = 0;
        }
    }
    return rows;
}

// Removes semantic spans that cannot fit the destination grid from the private
// logical snapshot. Scalar ranges compact with their lead cells, and the
// accepted Screen remains unchanged until the prepared replacement is swapped.
fn omitUnrepresentableSemanticWidths(
    lines: *LogicalSnapshot,
    cols: u16,
) void {
    if (cols >= 2) return;
    for (lines.logical_lines.items, 0..) |*line, line_index| {
        const storage: ?*scalar_storage.Storage = if (line.scalars) |*owner|
            owner
        else
            null;
        const original_len = line.cells.items.len;
        var source: usize = 0;
        var destination: usize = 0;
        var adjusted_cursor = if (lines.cursor_found and
            lines.cursor_line_index == line_index)
            lines.cursor_offset
        else
            0;
        while (source < original_len) {
            const cell = line.cells.items[source];
            if (isSemanticWideCell(cell) and isCellContinuation(cell)) {
                @panic("accepted logical continuation missing its lead");
            }
            const span: usize = if (isSemanticWideLead(cell)) cell.width else 1;
            if (span > cols) {
                std.debug.assert(source + span <= original_len);
                const continuation = line.cells.items[source + 1];
                if (!isSemanticWideCell(continuation) or
                    !isCellContinuation(continuation))
                    @panic("accepted logical semantic span mismatch");
                if (storage) |owner| {
                    clearAcceptedTail(owner, source, cell.combining_len);
                } else if (sidecarCount(cell) != 0) {
                    @panic("accepted logical scalar owner missing");
                }
                line.cells.items[source] = blank_cell;
                line.cells.items[source + 1] = blank_cell;
                if (adjusted_cursor > source) {
                    const removed_before_cursor = @min(
                        span,
                        adjusted_cursor - source,
                    );
                    adjusted_cursor -= @intCast(removed_before_cursor);
                }
                source += span;
                continue;
            }

            var offset: usize = 0;
            while (offset < span) : (offset += 1) {
                const source_cell = source + offset;
                const destination_cell = destination + offset;
                if (source_cell == destination_cell) continue;
                if (storage) |owner| {
                    owner.move(
                        source_cell,
                        line.cells.items[source_cell].combining_len,
                        destination_cell,
                        line.cells.items[destination_cell].combining_len,
                    ) catch @panic("accepted logical scalar compaction mismatch");
                } else if (sidecarCount(line.cells.items[source_cell]) != 0 or
                    sidecarCount(line.cells.items[destination_cell]) != 0)
                {
                    @panic("accepted logical scalar owner missing");
                }
                line.cells.items[destination_cell] = line.cells.items[source_cell];
                line.cells.items[source_cell] = blank_cell;
            }
            source += span;
            destination += span;
        }
        line.cells.items.len = destination;
        if (lines.cursor_found and lines.cursor_line_index == line_index)
            lines.cursor_offset = @intCast(@min(adjusted_cursor, destination));
    }
}

// Select the visible tail and hidden-history boundary from reflow output.
fn projectViewport(logical_line_count: u32, reflow: ReflowState, rows: u16) ResizeProjection {
    const total_rows: u32 = @intCast(reflow.rewrapped.items.len);
    const visible_rows_kept: u16 = @intCast(@min(@as(u32, rows), total_rows));
    const visible_start = total_rows - visible_rows_kept;
    const first_visible_line = firstLineForRowBounded(
        reflow.line_row_starts.items,
        reflow.line_row_counts.items,
        visible_start,
    ) orelse logical_line_count;
    const hidden_rows_in_first_visible_line: u16 = if (first_visible_line < logical_line_count)
        @intCast(visible_start - reflow.line_row_starts.items[@intCast(first_visible_line)])
    else
        0;

    std.debug.assert(visible_rows_kept <= rows);
    std.debug.assert(visible_rows_kept <= total_rows);
    std.debug.assert(visible_start <= total_rows);
    std.debug.assert(visible_start + visible_rows_kept == total_rows);
    std.debug.assert(first_visible_line <= logical_line_count);
    if (total_rows == 0) {
        std.debug.assert(first_visible_line == logical_line_count);
        std.debug.assert(hidden_rows_in_first_visible_line == 0);
    } else {
        std.debug.assert(first_visible_line < logical_line_count);
        std.debug.assert(reflow.line_row_starts.items[@intCast(first_visible_line)] <= visible_start);
        std.debug.assert(
            hidden_rows_in_first_visible_line <
                reflow.line_row_counts.items[@intCast(first_visible_line)],
        );
    }

    return .{
        .total_rows = total_rows,
        .visible_rows_kept = visible_rows_kept,
        .visible_start = visible_start,
        .first_visible_line = first_visible_line,
        .hidden_rows_in_first_visible_line = hidden_rows_in_first_visible_line,
    };
}

/// Allocate complete visible-grid replacement buffers for transfer to one Screen.
///
/// Allocation failure releases every completed buffer and returns no owner.
fn allocResizeBuffers(
    allocator: std.mem.Allocator,
    rows: u16,
    cols: u16,
    old_tab_stops: tab_stops_mod.State,
) std.mem.Allocator.Error!ResizeBuffers {
    const cell_count = resizeCellCount(rows, cols);
    var cells: ?[]ScreenCell = null;
    if (cell_count > 0) {
        const buf = try allocator.alloc(ScreenCell, cell_count);
        @memset(buf, blank_cell);
        cells = buf;
    }
    errdefer if (cells) |buf| allocator.free(buf);
    var scalars: ?scalar_storage.Storage = null;
    if (cell_count > 0) {
        scalars = scalar_storage.Storage.init(allocator, cell_count) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidCapacity => unreachable,
        };
    }
    errdefer if (scalars) |*storage| storage.deinit();

    var row_flags: ?[]u8 = null;
    if (rows > 0) {
        const buf = try allocator.alloc(u8, rows);
        @memset(buf, 0);
        row_flags = buf;
    }
    errdefer if (row_flags) |buf| allocator.free(buf);

    var tab_stops = try tab_stops_mod.State.initCopied(allocator, cols, old_tab_stops);
    errdefer tab_stops.deinit(allocator);

    std.debug.assert((cells != null) == (cell_count > 0));
    std.debug.assert((row_flags != null) == (rows > 0));
    std.debug.assert(tab_stops.ownsColumns(cols));
    if (cells) |buf| std.debug.assert(buf.len == cell_count);
    if (row_flags) |buf| std.debug.assert(buf.len == rows);

    return .{
        .cells = cells,
        .scalars = scalars,
        .row_flags = row_flags,
        .tab_stops = tab_stops,
    };
}

// Copy the selected visible rows into allocated replacement buffers.
fn copyVisibleRows(
    buffers: *ResizeBuffers,
    reflow: ReflowState,
    projection: ResizeProjection,
    cols: u16,
) error{ScalarCapacity}!void {
    const dst = buffers.cells orelse return;
    const dst_flags = buffers.row_flags orelse return;

    std.debug.assert(projection.visible_start + projection.visible_rows_kept <= projection.total_rows);
    std.debug.assert(projection.total_rows == screenCount32(reflow.rewrapped.items.len));
    std.debug.assert(screenCount32(dst_flags.len) >= projection.visible_rows_kept);
    std.debug.assert(screenCount32(dst.len) >= resizeCellCount(projection.visible_rows_kept, cols));
    std.debug.assert(
        screenCount32(reflow.flat_rows.items.len) ==
            screenCount32(reflow.rewrapped.items.len) * screenResizeColCount(cols),
    );

    var src_row = projection.visible_start;
    var view_row: u16 = 0;
    while (view_row < projection.visible_rows_kept) : (view_row += 1) {
        const src = reflow.rewrapped.items[@intCast(src_row)];
        const dst_start = rowStart(view_row, cols);
        std.debug.assert(dst_start + screenResizeColCount(cols) <= screenCount32(dst.len));
        @memcpy(
            dst[@intCast(dst_start)..@intCast(dst_start + screenResizeColCount(cols))],
            flatRowSlice(reflow.flat_rows.items, src, cols),
        );
        copyScalarCells(
            &reflow.scalars.?,
            flatRowSlice(reflow.flat_rows.items, src, cols),
            src.start,
            &buffers.scalars.?,
            dst_start,
            cols,
        ) catch |err| switch (err) {
            error.ScalarCapacity => return error.ScalarCapacity,
            error.InvalidRange => @panic("accepted reflow scalar mismatch"),
        };
        dst_flags[@intCast(view_row)] = Screen.rowFlags(src.wrapped, src.geometry);
        src_row += 1;
    }

    std.debug.assert(src_row == projection.visible_start + projection.visible_rows_kept);
}

// =============================================================================
// Resize and reflow proofs
// =============================================================================

test "resize allocation owners release partial state and remain reusable" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, collectSnapshotAllocation, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, reflowAllocation, .{});
    try std.testing.checkAllAllocationFailures(std.testing.allocator, resizeBuffersAllocation, .{});
}

fn collectSnapshotAllocation(allocator: std.mem.Allocator) !void {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 2, 4, 8);
    defer screen.deinit(std.testing.allocator);
    screen.applyScreen(.{ .write_text = "ABCDEFGHIJ" });

    var snapshot = screen.collectLogicalSnapshot(allocator) catch |err| {
        var retry = try screen.collectLogicalSnapshot(std.testing.allocator);
        retry.deinit(std.testing.allocator);
        return err;
    };
    snapshot.deinit(allocator);
}

fn reflowAllocation(allocator: std.mem.Allocator) !void {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 2, 4, 8);
    defer screen.deinit(std.testing.allocator);
    screen.applyScreen(.{ .write_text = "ABCDEFGHIJ" });
    var snapshot = try screen.collectLogicalSnapshot(std.testing.allocator);
    defer snapshot.deinit(std.testing.allocator);

    var state = reflowLogicalLines(allocator, snapshot, 3) catch |err| {
        var retry = try reflowLogicalLines(std.testing.allocator, snapshot, 3);
        retry.deinit(std.testing.allocator);
        return err;
    };
    state.deinit(allocator);
}

fn resizeBuffersAllocation(allocator: std.mem.Allocator) !void {
    var buffers = allocResizeBuffers(allocator, 3, 5, .empty) catch |err| {
        var retry = try allocResizeBuffers(std.testing.allocator, 3, 5, .empty);
        retry.deinit(std.testing.allocator);
        return err;
    };
    buffers.deinit(allocator);
}

fn canonicalLogicalStream(allocator: std.mem.Allocator, screen: *const Screen) ![]u21 {
    var snapshot = try screen.collectLogicalSnapshot(allocator);
    defer snapshot.deinit(allocator);

    var lines: std.ArrayList(u21) = .empty;
    defer lines.deinit(allocator);
    for (snapshot.logical_lines.items) |line| {
        try lines.append(allocator, 0);
        for (line.cells.items) |cell| try lines.append(allocator, @intCast(cell.codepoint));
    }
    return lines.toOwnedSlice(allocator);
}

test "reflow retains only the finite projected suffix when narrowing saturates history" {
    const allocator = std.testing.allocator;
    var screen = try Screen.initWithCellsAndHistory(allocator, 2, 6, 4);
    defer screen.deinit(allocator);

    screen.applyScreen(.{ .write_text = "AAAAAA\nBBBBBB\nCCCCCC\nDDDDDD\nEEEEEE" });
    const before = try canonicalLogicalStream(allocator, &screen);
    defer allocator.free(before);

    try screen.resize(allocator, 5, 3);
    try std.testing.expectEqual(@as(u32, 4), screen.historyCount());

    const narrowed = try canonicalLogicalStream(allocator, &screen);
    defer allocator.free(narrowed);
    try std.testing.expect(narrowed.len < before.len);
    try std.testing.expectEqual(@as(u21, 0), narrowed[0]);
    try std.testing.expectEqualSlices(
        u21,
        before[before.len - (narrowed.len - 1) ..],
        narrowed[1..],
    );

    try screen.resize(allocator, 5, 6);
    const widened = try canonicalLogicalStream(allocator, &screen);
    defer allocator.free(widened);
    try std.testing.expectEqualSlices(u21, narrowed, widened);
}

fn boundedCursorOffset(line: LogicalLine, has_cursor: bool, cursor_offset: u32) u32 {
    if (!has_cursor) return 0;
    return @min(cursor_offset, @as(u32, @intCast(line.cells.items.len)));
}

fn flatRowSlice(flat_rows: []const ScreenCell, row: RewrappedRow, cols: u16) []const ScreenCell {
    const start = row.start;
    std.debug.assert(start + screenResizeColCount(cols) <= screenCount32(flat_rows.len));
    return flat_rows[@intCast(start)..@intCast(start + screenResizeColCount(cols))];
}

fn resizeCellCount(rows: u16, cols: u16) u32 {
    return @as(u32, rows) * @as(u32, cols);
}

fn rowStart(row: u16, cols: u16) u32 {
    return @as(u32, row) * @as(u32, cols);
}

fn screenResizeColCount(cols: u16) u32 {
    return cols;
}

// Rectangular rendition helper shared by Screen editing paths.
fn applyRectAttrOps(target: *ScreenCellAttrs, attrs: []const u16, reverse: bool) bool {
    const before = target.*;
    for (attrs) |attr| {
        switch (attr) {
            0 => if (!reverse) {
                target.bold = false;
                target.dim = false;
                target.italic = false;
                target.underline = false;
                target.underline_style = .straight;
                target.blink = false;
                target.blink_fast = false;
                target.reverse = false;
                target.invisible = false;
                target.strikethrough = false;
            },
            1 => {
                if (reverse) target.bold = !target.bold else target.bold = true;
            },
            2 => {
                if (reverse) target.dim = !target.dim else target.dim = true;
            },
            3 => {
                if (reverse) target.italic = !target.italic else target.italic = true;
            },
            4 => {
                if (reverse) {
                    target.underline = !target.underline;
                    if (target.underline) target.underline_style = .straight;
                } else {
                    target.underline = true;
                    target.underline_style = .straight;
                }
            },
            5 => {
                if (reverse) target.blink = !target.blink else target.blink = true;
            },
            7 => {
                if (reverse) target.reverse = !target.reverse else target.reverse = true;
            },
            8 => {
                if (reverse) target.invisible = !target.invisible else target.invisible = true;
            },
            9 => {
                if (reverse) target.strikethrough = !target.strikethrough else target.strikethrough = true;
            },
            22 => {
                if (!reverse) {
                    target.bold = false;
                    target.dim = false;
                }
            },
            23 => {
                if (!reverse) target.italic = false;
            },
            24 => {
                if (!reverse) {
                    target.underline = false;
                    target.underline_style = .straight;
                }
            },
            25 => {
                if (!reverse) {
                    target.blink = false;
                    target.blink_fast = false;
                }
            },
            27 => {
                if (!reverse) target.reverse = false;
            },
            28 => {
                if (!reverse) target.invisible = false;
            },
            29 => {
                if (!reverse) target.strikethrough = false;
            },
            else => {},
        }
    }
    return !std.meta.eql(before, target.*);
}

// =============================================================================
// Projected history and logical-output proofs
// =============================================================================

test "projected history admission and eviction allocate nothing after initialization" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var screen = try Screen.initWithCellsAndHistory(failing.allocator(), 1, 2, 4);
    defer screen.deinit(failing.allocator());
    failing.fail_index = failing.alloc_index;

    var index: u8 = 0;
    while (index < 9) : (index += 1) {
        screen.clearRowRange(0, 0, screen.cols);
        var value = blank_cell;
        value.codepoint = 'a' + index;
        screen.cells.?[0] = value;
        screen.setRowWrapped(0, index % 3 != 2);
        screen.storeHistoryRow(0);
    }

    try std.testing.expect(!failing.has_induced_failure);
    try std.testing.expectEqual(@as(u64, 0), screen.history_loss_generation);
    try std.testing.expectEqual(@as(u32, screen.history_capacity), screen.history_count);
    try std.testing.expectEqual(@as(u32, 5), screen.history_row_base);
}

test "history constructor releases every partially acquired scalar owner" {
    const allocation_failure_limit = 32;
    var fail_index: usize = 0;
    while (fail_index < allocation_failure_limit) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{ .fail_index = fail_index },
        );
        var screen = Screen.initWithCellsAndHistory(
            failing.allocator(),
            2,
            4,
            8,
        ) catch |failure| {
            try std.testing.expectEqual(error.OutOfMemory, failure);
            try std.testing.expect(failing.has_induced_failure);
            continue;
        };
        screen.deinit(failing.allocator());
        try std.testing.expect(!failing.has_induced_failure);
        break;
    }
    try std.testing.expect(fail_index < allocation_failure_limit);
}

test "projected eviction freezes only the incomplete oldest logical prefix" {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 1, 2, 2);
    defer screen.deinit(std.testing.allocator);

    const rows = [_]struct { text: [2]u8, wrapped: bool }{
        .{ .text = "AA".*, .wrapped = true },
        .{ .text = "BB".*, .wrapped = true },
        .{ .text = "CC".*, .wrapped = true },
        .{ .text = "DD".*, .wrapped = false },
        .{ .text = "EE".*, .wrapped = false },
        .{ .text = "FF".*, .wrapped = false },
    };
    for (rows, 0..) |row, index| {
        screen.clearRowRange(0, 0, screen.cols);
        screen.cells.?[0].codepoint = row.text[0];
        screen.cells.?[1].codepoint = row.text[1];
        screen.setRowWrapped(0, row.wrapped);
        screen.storeHistoryRow(0);
        switch (index) {
            2 => {
                try std.testing.expect(screen.history_boundary_active);
                try std.testing.expectEqualStrings(
                    "AA",
                    screen.history_boundary_text.?[0..screen.history_boundary_stored],
                );
            },
            3 => try std.testing.expectEqualStrings(
                "AABB",
                screen.history_boundary_text.?[0..screen.history_boundary_stored],
            ),
            4 => try std.testing.expectEqualStrings(
                "AABBCC",
                screen.history_boundary_text.?[0..screen.history_boundary_stored],
            ),
            5 => {
                try std.testing.expect(!screen.history_boundary_active);
                try std.testing.expectEqual(@as(usize, 0), screen.history_boundary_total);
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(u32, 4), screen.history_row_base);
}

test "logical output byte bound evicts complete oldest lines" {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 2, 2, 4);
    defer screen.deinit(std.testing.allocator);
    const line_bytes = Screen.retained_output_bytes_max / 2 + 1;
    const first = try std.testing.allocator.alloc(u8, line_bytes);
    defer std.testing.allocator.free(first);
    @memset(first, 'a');
    screen.retainOutputText(first);
    const second = try std.testing.allocator.alloc(u8, line_bytes);
    defer std.testing.allocator.free(second);
    @memset(second, 'b');
    screen.retainOutputText(second);

    try std.testing.expectEqual(@as(u16, 1), screen.output_lines_count);
    try std.testing.expectEqual(@as(u64, 2), screen.output_lines.?[@intCast(screen.output_lines_start)].id);
    try std.testing.expectEqual(line_bytes, screen.output_bytes);
}

test "logical output byte ring preserves payload across physical wrap" {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 2, 2, 4);
    defer screen.deinit(std.testing.allocator);
    const first_len = 600 * 1024;
    const later_len = 300 * 1024;
    const first = try std.testing.allocator.alloc(u8, first_len);
    defer std.testing.allocator.free(first);
    @memset(first, 'a');
    const second = try std.testing.allocator.alloc(u8, later_len);
    defer std.testing.allocator.free(second);
    @memset(second, 'b');
    const third = try std.testing.allocator.alloc(u8, later_len);
    defer std.testing.allocator.free(third);
    @memset(third, 'c');

    screen.retainOutputText(first);
    screen.retainOutputText(second);
    screen.retainOutputText(third);

    try std.testing.expectEqual(@as(u16, 2), screen.output_lines_count);
    try std.testing.expectEqual(@as(usize, later_len * 2), screen.output_bytes);
    const lines = screen.output_lines.?;
    const second_line = lines[@intCast(screen.output_lines_start)];
    const third_slot = (screen.output_lines_start + 1) % @as(u32, @intCast(lines.len));
    const third_line = lines[@intCast(third_slot)];
    try std.testing.expectEqual(@as(u64, 2), second_line.id);
    try std.testing.expectEqual(@as(u64, 3), third_line.id);
    const storage = screen.output_text.?;
    const second_text = switch (second_line.value) {
        .text => |text| text,
        .loss => return error.UnexpectedOutputLoss,
    };
    const third_text = switch (third_line.value) {
        .text => |text| text,
        .loss => return error.UnexpectedOutputLoss,
    };
    const second_slices = second_text.slices(storage);
    try std.testing.expectEqual(@as(usize, later_len), second_slices[0].len);
    try std.testing.expectEqual(@as(usize, 0), second_slices[1].len);
    try std.testing.expectEqualSlices(u8, second, second_slices[0]);
    const third_slices = third_text.slices(storage);
    try std.testing.expect(third_slices[0].len > 0);
    try std.testing.expect(third_slices[1].len > 0);
    try std.testing.expectEqual(later_len, third_slices[0].len + third_slices[1].len);
    try std.testing.expectEqualSlices(u8, third[0..third_slices[0].len], third_slices[0]);
    try std.testing.expectEqualSlices(u8, third[third_slices[0].len..], third_slices[1]);
}

test "resize preserves a physically wrapped logical output ring" {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 2, 2, 4);
    defer screen.deinit(std.testing.allocator);
    const first_len = 600 * 1024;
    const later_len = 300 * 1024;
    const first = try std.testing.allocator.alloc(u8, first_len);
    defer std.testing.allocator.free(first);
    @memset(first, 'a');
    const second = try std.testing.allocator.alloc(u8, later_len);
    defer std.testing.allocator.free(second);
    @memset(second, 'b');
    const third = try std.testing.allocator.alloc(u8, later_len);
    defer std.testing.allocator.free(third);
    @memset(third, 'c');

    screen.retainOutputText(first);
    screen.retainOutputText(second);
    screen.retainOutputText(third);
    try screen.resize(std.testing.allocator, 3, 3);

    try std.testing.expectEqual(@as(u16, 2), screen.output_lines_count);
    const lines = screen.output_lines.?;
    const second_line = lines[@intCast(screen.output_lines_start)];
    const third_slot = (screen.output_lines_start + 1) % @as(u32, @intCast(lines.len));
    const third_line = lines[@intCast(third_slot)];
    const storage = screen.output_text.?;
    const second_text = switch (second_line.value) {
        .text => |text| text,
        .loss => return error.UnexpectedOutputLoss,
    };
    const third_text = switch (third_line.value) {
        .text => |text| text,
        .loss => return error.UnexpectedOutputLoss,
    };
    const second_slices = second_text.slices(storage);
    try std.testing.expectEqualSlices(u8, second, second_slices[0]);
    try std.testing.expectEqual(@as(usize, 0), second_slices[1].len);
    const third_slices = third_text.slices(storage);
    try std.testing.expectEqualSlices(u8, third[0..third_slices[0].len], third_slices[0]);
    try std.testing.expectEqualSlices(u8, third[third_slices[0].len..], third_slices[1]);
}

test "logical output accepts its exact per-line byte bound" {
    var screen = try Screen.initWithCellsAndHistory(std.testing.allocator, 2, 2, 2);
    defer screen.deinit(std.testing.allocator);
    const maximum = try std.testing.allocator.alloc(u8, logical_output_line_bytes_max);
    defer std.testing.allocator.free(maximum);
    @memset(maximum, 'x');
    screen.retainOutputText(maximum);

    try std.testing.expectEqual(@as(u16, 1), screen.output_lines_count);
    try std.testing.expectEqual(logical_output_line_bytes_max, screen.output_bytes);
}

test "scroll rows preserve scalar tails while transferring cell metadata" {
    var screen = try Screen.initWithCells(std.testing.allocator, 3, 2);
    defer screen.deinit(std.testing.allocator);

    var source = blank_cell;
    source.codepoint = 'a';
    source.combining_len = scalar_storage.maximum_scalars - 1;
    source.combining = .{ 0x0300, 0x0301, 0x0302 };
    var tail: [scalar_storage.maximum_tail_scalars]u32 = undefined;
    for (&tail, 0..) |*scalar, index|
        scalar.* = 0x0400 + @as(u32, @intCast(index));
    try screen.scalars.?.set(0, 0, &tail);
    screen.cells.?[0] = source;

    try std.testing.expect(screen.scrollDownRegion(0, 2, 1));
    try std.testing.expectEqual(blank_cell, screen.cells.?[@intCast(screen.rowStart(0))]);
    const middle = screen.rowStart(1);
    try std.testing.expectEqual(source, screen.cells.?[@intCast(middle)]);
    try std.testing.expectEqualSlices(
        u32,
        &tail,
        try screen.scalars.?.tail(middle, source.combining_len),
    );

    try std.testing.expect(screen.scrollUpRegion(0, 2, 1));
    const top = screen.rowStart(0);
    try std.testing.expectEqual(source, screen.cells.?[@intCast(top)]);
    try std.testing.expectEqualSlices(
        u32,
        &tail,
        try screen.scalars.?.tail(top, source.combining_len),
    );
}

test "partial row scroll preserves inline grapheme cells without scalar tails" {
    var screen = try Screen.initWithCells(std.testing.allocator, 4, 3);
    defer screen.deinit(std.testing.allocator);

    var source = blank_cell;
    source.codepoint = 'a';
    source.combining_len = 2;
    source.combining[0] = 0x0300;
    source.combining[1] = 0x0301;
    screen.cells.?[@intCast(screen.rowStart(1))] = source;

    try std.testing.expect(screen.scrollDownRegion(1, 3, 1));
    try std.testing.expectEqual(source, screen.cells.?[@intCast(screen.rowStart(2))]);
    try std.testing.expectEqual(scalar_storage.Range.none, screen.scalars.?.ranges[@intCast(screen.rowStart(2))]);
}

test "vertical absolute cursor movement clamps to the retained grid" {
    var screen = try Screen.initWithCells(std.testing.allocator, 2, 4);
    defer screen.deinit(std.testing.allocator);

    try std.testing.expect(screen.moveCursor(.{ .cursor_vertical_absolute = 21 }));
    try std.testing.expectEqual(@as(u16, 1), screen.cursor.row);
    try std.testing.expectEqual(@as(u16, 0), screen.cursor.col);
}
