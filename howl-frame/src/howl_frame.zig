//! Owns bounded immutable terminal frames and renderer acknowledgement.

const std = @import("std");
const howl_vt = @import("howl_vt");

/// Bounds trailing Unicode scalars copied with one visible terminal cell.
pub const max_combining: usize = 3;
/// Keeps one renderer borrow and one newer complete publication independent.
pub const slot_count: usize = 2;

/// Distinguishes normal, raised, and lowered terminal-cell baselines.
pub const Baseline = enum(u2) { normal, raised, lowered };

/// Retains one complete backend-neutral visual cell.
pub const Cell = struct {
    /// Stores the base Unicode scalar, or zero for a blank cell.
    codepoint: u21,
    /// Bounds initialized trailing scalars within `combining`.
    combining_len: u8,
    /// Stores up to three trailing Unicode scalars.
    combining: [max_combining]u21,
    /// Retains the source cluster width in terminal cells.
    width: u8,
    /// Retains the source cluster height in terminal rows.
    height: u8,
    /// Identifies this cell's horizontal position inside a multicell cluster.
    x: u8,
    /// Identifies this cell's vertical position inside a multicell cluster.
    y: u8,
    /// Copies the resolved foreground color for this publication.
    foreground: howl_vt.Terminal.Rgb,
    /// Copies the resolved background color for this publication.
    background: howl_vt.Terminal.Rgb,
    /// Copies the resolved underline color for this publication.
    underline_color: howl_vt.Terminal.Rgb,
    /// Selects the terminal-requested font slot.
    font: u4,
    /// Selects normal, raised, or lowered baseline placement.
    baseline: Baseline,
    /// Retains the terminal's bold rendition request.
    bold: bool,
    /// Retains the terminal's dim rendition request.
    dim: bool,
    /// Retains the terminal's italic rendition request.
    italic: bool,
    /// Retains the terminal's ordinary blink request.
    blink: bool,
    /// Retains the terminal's rapid blink request.
    blink_fast: bool,
    /// Retains whether glyph content is invisible.
    invisible: bool,
    /// Retains whether underline rendering is enabled.
    underline: bool,
    /// Retains whether strikethrough rendering is enabled.
    strikethrough: bool,
    /// Selects the exact terminal underline shape.
    underline_style: howl_vt.Terminal.UnderlineStyle,
    /// Identifies retained hyperlink state without choosing host interaction.
    link_id: u32,
};

/// Copies one row's DEC geometry without prescribing pixel scaling.
pub const LineGeometry = enum(u2) {
    single_width,
    double_width,
    double_height_top,
    double_height_bottom,
};

/// Copies one nonzero host-provided terminal cell size in logical pixels.
pub const CellPixelSize = struct {
    /// Stores one nonzero logical-pixel cell width.
    width: u32,
    /// Stores one nonzero logical-pixel cell height.
    height: u32,
};

/// Copies the terminal cursor and its resolved presentation colors.
pub const Cursor = struct {
    /// Identifies the in-bounds terminal row.
    row: u16,
    /// Identifies the in-bounds terminal column.
    col: u16,
    /// Reports whether the terminal requests cursor presentation.
    visible: bool,
    /// Selects the resolved cursor shape.
    shape: howl_vt.Terminal.CursorShape,
    /// Retains the cursor blink intent without owning its timer.
    blink: bool,
    /// Copies the resolved cursor background color.
    color: howl_vt.Terminal.Rgb,
    /// Copies the resolved glyph color beneath the cursor.
    text_color: howl_vt.Terminal.Rgb,
};

/// Identifies one selection endpoint in projected terminal rows.
pub const SelectionPoint = struct {
    /// Identifies a stable projected row, including retained history.
    row: i32,
    /// Identifies a bounded terminal column.
    col: u16,
};

/// Copies the active terminal selection without host interaction policy.
pub const Selection = struct {
    /// Reports whether the operator is still extending this selection.
    selecting: bool,
    /// Copies the anchored endpoint.
    start: SelectionPoint,
    /// Copies the current endpoint.
    end: SelectionPoint,
};

/// Describes one inclusive changed cell interval or a clean row.
pub const RowDamage = struct {
    /// Reports whether this row has an accumulated changed interval.
    dirty: bool = false,
    /// Identifies the first changed column when dirty.
    start: u16 = 0,
    /// Identifies the last changed column when dirty.
    end: u16 = 0,
};

/// Borrows complete redraw or accumulated per-row cell damage.
pub const Damage = struct {
    /// Requires complete redraw when continuity or geometry is unsafe.
    full: bool,
    /// Borrows one accumulated interval per visible row.
    rows: []const RowDamage,
};

/// Borrows one immutable complete terminal-local visual generation.
pub const TerminalFrame = struct {
    /// Identifies this publisher-owned frame without wrap or reuse.
    generation: u64,
    /// Copies the exact VT surface-publication identity.
    surface_generation: u64,
    /// Copies the exact VT mutation identity represented by the cells.
    terminal_generation: u64,
    /// Copies the terminal owner's accepted geometry identity.
    geometry_generation: u64,
    /// Reports the complete nonzero visible row count.
    rows: u16,
    /// Reports the complete nonzero visible column count.
    cols: u16,
    /// Copies optional nonzero host-provided cell dimensions.
    cell_pixels: ?CellPixelSize,
    /// Borrows exactly `rows × cols` immutable row-major cells.
    cells: []const Cell,
    /// Borrows exactly one immutable DEC geometry per visible row.
    line_geometry: []const LineGeometry,
    /// Copies complete cursor presentation facts.
    cursor: Cursor,
    /// Copies the active selection when one exists.
    selection: ?Selection,
    /// Reports which VT screen supplied this publication.
    alternate_screen: bool,
    /// Identifies the oldest retained projected history row.
    history_row_base: u32,
    /// Reports retained rows available above the primary screen.
    history_count: u32,
    /// Reports the projected-history offset copied into this frame.
    scrollback_offset: u32,
    /// Reports whether terminal mouse tracking owns pointer input.
    mouse_reporting: bool,
    /// Borrows cumulative damage since the latest released frame.
    damage: Damage,
};

/// Reports invalid configured storage or allocation before ownership transfers.
pub const InitError = std.mem.Allocator.Error || error{InvalidBounds};
/// Reports invalid geometry, allocation failure, or immutable borrowed storage.
pub const PrepareResizeError = InitError || error{BorrowedFrames};

/// Reports the exact invalid copied fact or exhausted publication identity.
pub const PublishError = error{
    SurfaceBounds,
    InvalidCell,
    InvalidCellPixels,
    InvalidCursor,
    InvalidDamage,
    InvalidSelection,
    GenerationExhausted,
};

/// Distinguishes a retained generation from immediate slot saturation.
pub const PublishResult = union(enum) {
    published: u64,
    saturated,
};

/// Reports stale identity or release of a generation that is not borrowed.
pub const ReleaseError = error{ StaleGeneration, NotBorrowed };

const SlotState = enum { free, ready, borrowed };

const Slot = struct {
    cells: []Cell,
    line_geometry: []LineGeometry,
    damage: []RowDamage,
    state: SlotState = .free,
    generation: u64 = 0,
    surface_generation: u64 = 0,
    terminal_generation: u64 = 0,
    geometry_generation: u64 = 0,
    rows: u16 = 0,
    cols: u16 = 0,
    cell_pixels: ?CellPixelSize = null,
    cursor: Cursor = undefined,
    selection: ?Selection = null,
    alternate_screen: bool = false,
    history_row_base: u32 = 0,
    history_count: u32 = 0,
    scrollback_offset: u32 = 0,
    mouse_reporting: bool = false,
    full_redraw: bool = true,
};

/// Owns replacement publication storage until committed or rolled back.
/// Preparation reserves the publisher against new borrows; `deinit` restores
/// the prior publisher unchanged unless `commit` consumed this value.
pub const PreparedResize = struct {
    owner: *Publisher,
    pending_damage: []RowDamage,
    slots: [slot_count]Slot,
    rows: u16,
    cols: u16,
    active: bool = true,

    /// Installs the prepared storage and releases the resize reservation.
    pub fn commit(self: *PreparedResize) void {
        std.debug.assert(self.active);
        self.owner.commitResize(self);
        self.active = false;
    }

    /// Frees uncommitted storage and restores frame borrowing.
    pub fn deinit(self: *PreparedResize) void {
        if (!self.active) return;
        self.owner.cancelResize();
        deinitStorage(self.owner.allocator, self.pending_damage, self.slots);
        self.active = false;
    }
};

/// Borrows one immutable frame until its exact generation is released.
pub const Borrow = struct {
    /// Retains the publisher required for exact release.
    owner: *Publisher,
    /// Borrows immutable slot slices until release.
    frame: TerminalFrame,

    /// Releases this exact generation, invalidates the borrow, and reports
    /// whether prior saturation requires the producer to publish again.
    pub fn release(self: *Borrow) ReleaseError!bool {
        const publication_pending = try self.owner.release(self.frame.generation);
        self.* = undefined;
        return publication_pending;
    }
};

/// Owns two bounded frame slots and cumulative unacknowledged damage.
/// One mutex serializes the complete grid copy with renderer borrow and
/// release. Renderer use of a borrowed frame occurs outside that mutex, and
/// borrowed slot bytes remain immutable until exact release.
pub const Publisher = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    capacity_rows: u16,
    capacity_cols: u16,
    pending_damage: []RowDamage,
    pending_full: bool = true,
    pending_unpublished: bool = false,
    slots: [slot_count]Slot,
    newest_slot: ?u1 = null,
    last_generation: u64 = 0,
    last_rows: u16 = 0,
    last_cols: u16 = 0,
    last_geometry_generation: u64 = 0,
    last_scrollback_offset: u32 = 0,
    resizing: bool = false,

    /// Allocates exactly two frame capacities and one cumulative-damage set.
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        capacity_rows: u16,
        capacity_cols: u16,
    ) InitError!Publisher {
        if (capacity_rows == 0 or capacity_cols == 0) return error.InvalidBounds;
        const storage = try initStorage(allocator, capacity_rows, capacity_cols);
        return .{
            .allocator = allocator,
            .io = io,
            .capacity_rows = capacity_rows,
            .capacity_cols = capacity_cols,
            .pending_damage = storage.pending_damage,
            .slots = storage.slots,
        };
    }

    /// Releases all storage after the caller has returned every borrow.
    pub fn deinit(self: *Publisher) void {
        std.debug.assert(!self.resizing);
        for (self.slots) |slot| {
            std.debug.assert(slot.state != .borrowed);
        }
        deinitStorage(self.allocator, self.pending_damage, self.slots);
        self.* = undefined;
    }

    /// Reserves borrowing and allocates exact replacement storage. Any active
    /// borrow rejects preparation without changing the publisher. Publication
    /// and resize preparation are externally serialized by the terminal owner.
    pub fn prepareResize(
        self: *Publisher,
        rows: u16,
        cols: u16,
    ) PrepareResizeError!PreparedResize {
        if (rows == 0 or cols == 0) return error.InvalidBounds;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        std.debug.assert(!self.resizing);
        for (self.slots) |slot| if (slot.state == .borrowed)
            return error.BorrowedFrames;
        self.resizing = true;
        const storage = initStorage(self.allocator, rows, cols) catch |failure| {
            self.resizing = false;
            return failure;
        };
        return .{
            .owner = self,
            .pending_damage = storage.pending_damage,
            .slots = storage.slots,
            .rows = rows,
            .cols = cols,
        };
    }

    /// Copies one VT publication while holding the publisher mutex. If both
    /// slots are borrowed, saturation returns without waiting, preserves
    /// pending damage, and consumes no frame generation.
    pub fn publish(
        self: *Publisher,
        surface: howl_vt.Terminal.SurfacePublication,
        geometry_generation: u64,
        cell_pixels: ?CellPixelSize,
    ) PublishError!PublishResult {
        try self.validateSurface(surface, cell_pixels);
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        std.debug.assert(!self.resizing);
        if (self.last_generation == std.math.maxInt(u64))
            return error.GenerationExhausted;

        const view = surface.snapshot.view;
        if (self.last_generation == 0 or
            self.last_rows != view.rows or self.last_cols != view.cols or
            self.last_geometry_generation != geometry_generation or
            self.last_scrollback_offset != surface.scrollback_offset)
            self.pending_full = true;
        self.accumulateDamage(surface);

        const slot_index = self.writableSlot() orelse {
            self.pending_unpublished = true;
            return .saturated;
        };
        const generation = self.last_generation + 1;
        self.copyFrame(
            &self.slots[slot_index],
            surface,
            generation,
            geometry_generation,
            cell_pixels,
        );
        if (self.newest_slot) |previous_index| {
            const previous = &self.slots[previous_index];
            if (previous_index != slot_index and previous.state == .ready)
                previous.state = .free;
        }
        self.slots[slot_index].state = .ready;
        self.newest_slot = @intCast(slot_index);
        self.last_generation = generation;
        self.last_rows = view.rows;
        self.last_cols = view.cols;
        self.last_geometry_generation = geometry_generation;
        self.last_scrollback_offset = surface.scrollback_offset;
        self.pending_unpublished = false;
        return .{ .published = generation };
    }

    /// Borrows the newest unconsumed complete generation, if one exists.
    pub fn borrowNewest(self: *Publisher) ?Borrow {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.resizing) return null;
        const slot_index = self.newest_slot orelse return null;
        const slot = &self.slots[slot_index];
        if (slot.state != .ready) return null;
        slot.state = .borrowed;
        return .{ .owner = self, .frame = frameFromSlot(slot) };
    }

    /// Reports the newest retained identity, including an already borrowed one.
    pub fn newestGeneration(self: *Publisher) u64 {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.last_generation;
    }

    /// Releases one exact borrowed generation and reports whether saturation
    /// left a publication pending. Only release of the current newest frame
    /// with no unpublished mutation retires cumulative damage.
    pub fn release(self: *Publisher, generation: u64) ReleaseError!bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        for (&self.slots) |*slot| {
            if (slot.generation != generation) continue;
            if (slot.state != .borrowed) return error.NotBorrowed;
            slot.state = .free;
            if (generation == self.last_generation and !self.pending_unpublished) {
                self.pending_full = false;
                @memset(self.pending_damage, .{});
            }
            return self.pending_unpublished;
        }
        return error.StaleGeneration;
    }

    fn writableSlot(self: *Publisher) ?usize {
        if (self.newest_slot) |index| {
            if (self.slots[index].state == .ready) return index;
        }
        for (self.slots, 0..) |slot, index| {
            if (slot.state != .borrowed) return index;
        }
        return null;
    }

    fn commitResize(self: *Publisher, prepared: *PreparedResize) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        std.debug.assert(self.resizing);
        std.debug.assert(prepared.owner == self);
        for (self.slots) |slot| std.debug.assert(slot.state != .borrowed);
        deinitStorage(self.allocator, self.pending_damage, self.slots);
        self.pending_damage = prepared.pending_damage;
        self.slots = prepared.slots;
        self.capacity_rows = prepared.rows;
        self.capacity_cols = prepared.cols;
        self.pending_full = true;
        self.pending_unpublished = true;
        self.newest_slot = null;
        self.resizing = false;
    }

    fn cancelResize(self: *Publisher) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        std.debug.assert(self.resizing);
        self.resizing = false;
    }

    fn validateSurface(
        self: *const Publisher,
        surface: howl_vt.Terminal.SurfacePublication,
        cell_pixels: ?CellPixelSize,
    ) PublishError!void {
        const view = surface.snapshot.view;
        if (view.rows == 0 or view.cols == 0 or
            view.rows > self.capacity_rows or view.cols > self.capacity_cols)
            return error.SurfaceBounds;
        if (view.cursor_row >= view.rows or view.cursor_col >= view.cols)
            return error.InvalidCursor;
        if (cell_pixels) |size| if (size.width == 0 or size.height == 0)
            return error.InvalidCellPixels;
        if (surface.snapshot.selection) |selection| {
            if (selection.start.col >= view.cols or selection.end.col >= view.cols)
                return error.InvalidSelection;
        }
        if (surface.snapshot.dirty) |dirty| {
            if (dirty.start_row > dirty.end_row or dirty.end_row >= view.rows or
                dirty.dirty_cols_start.len != view.rows or
                dirty.dirty_cols_end.len != view.rows)
                return error.InvalidDamage;
            var row = dirty.start_row;
            while (row <= dirty.end_row) : (row += 1) {
                const start = dirty.dirty_cols_start[row];
                const end = dirty.dirty_cols_end[row];
                // VT bounds the outer dirty-row interval, while untouched
                // rows inside it retain this exact empty sentinel.
                if (start == view.cols and end == 0) continue;
                if (start > end or end >= view.cols)
                    return error.InvalidDamage;
            }
        }
        for (0..view.rows) |row| for (0..view.cols) |col| {
            const cell = view.cellInfoAt(@intCast(row), @intCast(col));
            if (cell.codepoint > std.math.maxInt(u21) or
                cell.combining_len > max_combining)
                return error.InvalidCell;
            for (cell.combining[0..cell.combining_len]) |codepoint|
                if (codepoint > std.math.maxInt(u21)) return error.InvalidCell;
        };
    }

    fn accumulateDamage(
        self: *Publisher,
        surface: howl_vt.Terminal.SurfacePublication,
    ) void {
        if (self.pending_full) return;
        const dirty = surface.snapshot.dirty orelse return;
        var row = dirty.start_row;
        while (row <= dirty.end_row) : (row += 1) {
            if (dirty.dirty_cols_start[row] == surface.snapshot.view.cols and
                dirty.dirty_cols_end[row] == 0) continue;
            const next = RowDamage{
                .dirty = true,
                .start = dirty.dirty_cols_start[row],
                .end = dirty.dirty_cols_end[row],
            };
            const current = &self.pending_damage[row];
            if (!current.dirty) {
                current.* = next;
            } else {
                current.start = @min(current.start, next.start);
                current.end = @max(current.end, next.end);
            }
        }
    }

    fn copyFrame(
        self: *Publisher,
        slot: *Slot,
        surface: howl_vt.Terminal.SurfacePublication,
        generation: u64,
        geometry_generation: u64,
        cell_pixels: ?CellPixelSize,
    ) void {
        const view = surface.snapshot.view;
        for (0..view.rows) |row| {
            slot.line_geometry[row] = switch (view.lineGeometry(@intCast(row))) {
                .single_width => .single_width,
                .double_width => .double_width,
                .double_height_top => .double_height_top,
                .double_height_bottom => .double_height_bottom,
            };
            for (0..view.cols) |col| {
                const source = view.cellInfoAt(@intCast(row), @intCast(col));
                var foreground = source.attrs.fg.resolve(
                    surface.presentation.foreground,
                    &surface.presentation.palette,
                );
                var background = source.attrs.bg.resolve(
                    surface.presentation.background,
                    &surface.presentation.palette,
                );
                if (source.attrs.reverse != surface.presentation.reverse_screen)
                    std.mem.swap(howl_vt.Terminal.Rgb, &foreground, &background);
                var cell = Cell{
                    .codepoint = @intCast(source.codepoint),
                    .combining_len = source.combining_len,
                    .combining = @splat(0),
                    .width = source.width,
                    .height = source.height,
                    .x = source.x,
                    .y = source.y,
                    .foreground = foreground,
                    .background = background,
                    .underline_color = source.attrs.underline_color.resolve(
                        foreground,
                        &surface.presentation.palette,
                    ),
                    .font = source.attrs.font,
                    .baseline = switch (source.attrs.baseline) {
                        .normal => .normal,
                        .raised => .raised,
                        .lowered => .lowered,
                    },
                    .bold = source.attrs.bold,
                    .dim = source.attrs.dim,
                    .italic = source.attrs.italic,
                    .blink = source.attrs.blink,
                    .blink_fast = source.attrs.blink_fast,
                    .invisible = source.attrs.invisible,
                    .underline = source.attrs.underline,
                    .strikethrough = source.attrs.strikethrough,
                    .underline_style = source.attrs.underline_style,
                    .link_id = source.attrs.link_id,
                };
                for (source.combining[0..source.combining_len], 0..) |codepoint, index|
                    cell.combining[index] = @intCast(codepoint);
                slot.cells[row * view.cols + col] = cell;
            }
        }
        @memcpy(slot.damage[0..view.rows], self.pending_damage[0..view.rows]);
        slot.generation = generation;
        slot.surface_generation = surface.snapshot_seq;
        slot.terminal_generation = surface.dirty_generation;
        slot.geometry_generation = geometry_generation;
        slot.rows = view.rows;
        slot.cols = view.cols;
        slot.cell_pixels = cell_pixels;
        slot.cursor = .{
            .row = view.cursor_row,
            .col = view.cursor_col,
            .visible = view.cursor_visible,
            .shape = view.cursor_shape,
            .blink = view.cursor_blink,
            .color = surface.presentation.cursor orelse surface.presentation.foreground,
            .text_color = surface.presentation.cursor_text orelse surface.presentation.background,
        };
        slot.selection = if (surface.snapshot.selection) |selection| .{
            .selecting = selection.selecting,
            .start = .{ .row = selection.start.row, .col = selection.start.col },
            .end = .{ .row = selection.end.row, .col = selection.end.col },
        } else null;
        slot.alternate_screen = view.is_alternate_screen;
        slot.history_row_base = surface.history_row_base;
        slot.history_count = surface.history_count;
        slot.scrollback_offset = surface.scrollback_offset;
        slot.mouse_reporting = surface.mouse_reporting;
        slot.full_redraw = self.pending_full;
    }
};

fn frameFromSlot(slot: *const Slot) TerminalFrame {
    const cell_count = @as(usize, slot.rows) * slot.cols;
    return .{
        .generation = slot.generation,
        .surface_generation = slot.surface_generation,
        .terminal_generation = slot.terminal_generation,
        .geometry_generation = slot.geometry_generation,
        .rows = slot.rows,
        .cols = slot.cols,
        .cell_pixels = slot.cell_pixels,
        .cells = slot.cells[0..cell_count],
        .line_geometry = slot.line_geometry[0..slot.rows],
        .cursor = slot.cursor,
        .selection = slot.selection,
        .alternate_screen = slot.alternate_screen,
        .history_row_base = slot.history_row_base,
        .history_count = slot.history_count,
        .scrollback_offset = slot.scrollback_offset,
        .mouse_reporting = slot.mouse_reporting,
        .damage = .{ .full = slot.full_redraw, .rows = slot.damage[0..slot.rows] },
    };
}

fn deinitSlot(allocator: std.mem.Allocator, slot: Slot) void {
    allocator.free(slot.damage);
    allocator.free(slot.line_geometry);
    allocator.free(slot.cells);
}

const Storage = struct {
    pending_damage: []RowDamage,
    slots: [slot_count]Slot,
};

fn initStorage(
    allocator: std.mem.Allocator,
    rows: u16,
    cols: u16,
) InitError!Storage {
    const capacity_cells = std.math.mul(usize, rows, cols) catch
        return error.InvalidBounds;
    const pending_damage = try allocator.alloc(RowDamage, rows);
    errdefer allocator.free(pending_damage);
    @memset(pending_damage, .{});
    var slots: [slot_count]Slot = undefined;
    var initialized: usize = 0;
    errdefer for (slots[0..initialized]) |slot| deinitSlot(allocator, slot);
    while (initialized < slots.len) : (initialized += 1) {
        slots[initialized] = try initSlot(allocator, capacity_cells, rows);
    }
    return .{ .pending_damage = pending_damage, .slots = slots };
}

fn deinitStorage(
    allocator: std.mem.Allocator,
    pending_damage: []RowDamage,
    slots: [slot_count]Slot,
) void {
    for (slots) |slot| deinitSlot(allocator, slot);
    allocator.free(pending_damage);
}

fn initSlot(
    allocator: std.mem.Allocator,
    capacity_cells: usize,
    capacity_rows: u16,
) std.mem.Allocator.Error!Slot {
    const cells = try allocator.alloc(Cell, capacity_cells);
    errdefer allocator.free(cells);
    const line_geometry = try allocator.alloc(LineGeometry, capacity_rows);
    errdefer allocator.free(line_geometry);
    const damage = try allocator.alloc(RowDamage, capacity_rows);
    return .{ .cells = cells, .line_geometry = line_geometry, .damage = damage };
}

fn expectPublished(result: PublishResult) !u64 {
    return switch (result) {
        .published => |generation| generation,
        .saturated => error.UnexpectedSaturation,
    };
}

test "complete immutable frame reconstructs VT visual truth" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    try std.testing.expect((try terminal.feed("A\x1b[3mB\r\nC\x1b#6")).state_changed);
    terminal.startSelection(0, 0);
    terminal.updateSelection(1, 0);
    terminal.finishSelection();
    var publisher = try Publisher.init(std.testing.allocator, std.testing.io, 2, 4);
    defer publisher.deinit();

    const source = terminal.surfaceSnapshot();
    const generation = try expectPublished(try publisher.publish(
        source,
        7,
        .{ .width = 9, .height = 18 },
    ));
    try std.testing.expect(terminal.ackSurface(source.snapshot_seq));
    var borrowed = publisher.borrowNewest().?;
    defer std.debug.assert(!(borrowed.release() catch unreachable));
    const frame = borrowed.frame;
    try std.testing.expectEqual(@as(u64, 1), generation);
    try std.testing.expectEqual(source.snapshot_seq, frame.surface_generation);
    try std.testing.expectEqual(source.dirty_generation, frame.terminal_generation);
    try std.testing.expectEqual(@as(u64, 7), frame.geometry_generation);
    try std.testing.expectEqual(@as(u16, 2), frame.rows);
    try std.testing.expectEqual(@as(u16, 4), frame.cols);
    try std.testing.expectEqual(@as(usize, 8), frame.cells.len);
    try std.testing.expectEqual(@as(u21, 'A'), frame.cells[0].codepoint);
    try std.testing.expect(frame.cells[1].italic);
    try std.testing.expectEqual(@as(u21, 'C'), frame.cells[4].codepoint);
    try std.testing.expectEqual(CellPixelSize{ .width = 9, .height = 18 }, frame.cell_pixels.?);
    try std.testing.expectEqual(LineGeometry.double_width, frame.line_geometry[1]);
    try std.testing.expectEqual(SelectionPoint{ .row = 0, .col = 0 }, frame.selection.?.start);
    try std.testing.expectEqual(SelectionPoint{ .row = 1, .col = 0 }, frame.selection.?.end);
    try std.testing.expect(frame.damage.full);
}

test "skipped publications retain cumulative damage until newest release" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 4);
    defer terminal.deinit();
    var publisher = try Publisher.init(std.testing.allocator, std.testing.io, 2, 4);
    defer publisher.deinit();

    var source = terminal.surfaceSnapshot();
    try std.testing.expectEqual(
        @as(u64, 1),
        try expectPublished(try publisher.publish(source, 0, null)),
    );
    try std.testing.expect(terminal.ackSurface(source.snapshot_seq));
    var initial = publisher.borrowNewest().?;
    try std.testing.expect(!try initial.release());

    try std.testing.expect((try terminal.feed("A")).state_changed);
    source = terminal.surfaceSnapshot();
    try std.testing.expectEqual(
        @as(u64, 2),
        try expectPublished(try publisher.publish(source, 0, null)),
    );
    try std.testing.expect(terminal.ackSurface(source.snapshot_seq));
    try std.testing.expect((try terminal.feed("\x1b[2;4HZ")).state_changed);
    source = terminal.surfaceSnapshot();
    const newest = try expectPublished(try publisher.publish(source, 0, null));
    try std.testing.expect(terminal.ackSurface(source.snapshot_seq));

    var frame = publisher.borrowNewest().?;
    try std.testing.expectEqual(newest, frame.frame.generation);
    try std.testing.expect(!frame.frame.damage.full);
    try std.testing.expect(frame.frame.damage.rows[0].dirty);
    try std.testing.expect(frame.frame.damage.rows[1].dirty);
    try std.testing.expect(!try frame.release());

    try std.testing.expect((try terminal.feed("\x1b[2;3HY")).state_changed);
    source = terminal.surfaceSnapshot();
    try std.testing.expectEqual(
        @as(u64, 4),
        try expectPublished(try publisher.publish(source, 0, null)),
    );
    var after_ack = publisher.borrowNewest().?;
    try std.testing.expect(!after_ack.frame.damage.full);
    try std.testing.expect(!after_ack.frame.damage.rows[0].dirty);
    try std.testing.expect(after_ack.frame.damage.rows[1].dirty);
    try std.testing.expect(!try after_ack.release());
}

test "alternate-screen sparse dirty rows publish without inventing middle damage" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 3, 4);
    defer terminal.deinit();
    var publisher = try Publisher.init(std.testing.allocator, std.testing.io, 3, 4);
    defer publisher.deinit();

    var source = terminal.surfaceSnapshot();
    try std.testing.expectEqual(@as(u64, 1), try expectPublished(try publisher.publish(source, 0, null)));
    try std.testing.expect(terminal.ackSurface(source.snapshot_seq));
    var initial = publisher.borrowNewest().?;
    try std.testing.expect(!try initial.release());

    try std.testing.expect((try terminal.feed("\x1b[?1049h")).state_changed);
    source = terminal.surfaceSnapshot();
    try std.testing.expectEqual(@as(u64, 2), try expectPublished(try publisher.publish(source, 0, null)));
    try std.testing.expect(terminal.ackSurface(source.snapshot_seq));
    var alternate = publisher.borrowNewest().?;
    try std.testing.expect(alternate.frame.alternate_screen);
    try std.testing.expect(!try alternate.release());

    try std.testing.expect((try terminal.feed("\x1b[1;1HA\x1b[3;4HZ")).state_changed);
    source = terminal.surfaceSnapshot();
    try std.testing.expectEqual(@as(u16, 0), source.snapshot.dirty.?.start_row);
    try std.testing.expectEqual(@as(u16, 2), source.snapshot.dirty.?.end_row);
    try std.testing.expectEqual(source.snapshot.view.cols, source.snapshot.dirty.?.dirty_cols_start[1]);
    try std.testing.expectEqual(@as(u16, 0), source.snapshot.dirty.?.dirty_cols_end[1]);
    try std.testing.expectEqual(@as(u64, 3), try expectPublished(try publisher.publish(source, 0, null)));
    try std.testing.expect(terminal.ackSurface(source.snapshot_seq));
    var sparse = publisher.borrowNewest().?;
    try std.testing.expect(sparse.frame.damage.rows[0].dirty);
    try std.testing.expect(!sparse.frame.damage.rows[1].dirty);
    try std.testing.expect(sparse.frame.damage.rows[2].dirty);
    try std.testing.expect(!try sparse.release());
}

test "new publication replaces only the unread ready generation" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 1, 2);
    defer terminal.deinit();
    var publisher = try Publisher.init(std.testing.allocator, std.testing.io, 1, 2);
    defer publisher.deinit();

    const first = try expectPublished(try publisher.publish(
        terminal.surfaceSnapshot(),
        1,
        null,
    ));
    try std.testing.expect((try terminal.feed("A")).state_changed);
    const second = try expectPublished(try publisher.publish(
        terminal.surfaceSnapshot(),
        2,
        null,
    ));

    try std.testing.expectEqual(@as(u64, 1), first);
    try std.testing.expectEqual(@as(u64, 2), second);
    try std.testing.expectError(error.StaleGeneration, publisher.release(first));
    var newest = publisher.borrowNewest().?;
    try std.testing.expectEqual(second, newest.frame.generation);
    try std.testing.expectEqual(@as(u64, 2), newest.frame.geometry_generation);
    try std.testing.expectEqual(@as(u21, 'A'), newest.frame.cells[0].codepoint);
    try std.testing.expect(newest.frame.damage.full);
    try std.testing.expect(!try newest.release());
}

test "invalid publication cannot mutate retained frame or pending damage" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 1, 2);
    defer terminal.deinit();
    var publisher = try Publisher.init(std.testing.allocator, std.testing.io, 1, 2);
    defer publisher.deinit();

    const generation = try expectPublished(try publisher.publish(
        terminal.surfaceSnapshot(),
        9,
        null,
    ));
    var retained = publisher.borrowNewest().?;
    try std.testing.expectError(
        error.InvalidCellPixels,
        publisher.publish(
            terminal.surfaceSnapshot(),
            10,
            .{ .width = 1, .height = 0 },
        ),
    );

    try std.testing.expectEqual(generation, publisher.newestGeneration());
    try std.testing.expectEqual(generation, retained.frame.generation);
    try std.testing.expectEqual(@as(u64, 9), retained.frame.geometry_generation);
    try std.testing.expect(publisher.pending_full);
    try std.testing.expect(!publisher.pending_unpublished);
    try std.testing.expect(!publisher.pending_damage[0].dirty);
    try std.testing.expect(!try retained.release());
}

test "two borrowed slots saturate without consuming identity or damage" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 1, 4);
    defer terminal.deinit();
    var publisher = try Publisher.init(std.testing.allocator, std.testing.io, 1, 4);
    defer publisher.deinit();

    var source = terminal.surfaceSnapshot();
    try std.testing.expectEqual(
        @as(u64, 1),
        try expectPublished(try publisher.publish(source, 0, null)),
    );
    try std.testing.expect(terminal.ackSurface(source.snapshot_seq));
    var first = publisher.borrowNewest().?;
    try std.testing.expect((try terminal.feed("A")).state_changed);
    source = terminal.surfaceSnapshot();
    try std.testing.expectEqual(
        @as(u64, 2),
        try expectPublished(try publisher.publish(source, 0, null)),
    );
    try std.testing.expect(terminal.ackSurface(source.snapshot_seq));
    var second = publisher.borrowNewest().?;

    try std.testing.expect((try terminal.feed("B")).state_changed);
    source = terminal.surfaceSnapshot();
    try std.testing.expectEqual(PublishResult.saturated, try publisher.publish(source, 0, null));
    try std.testing.expectEqual(@as(u64, 2), publisher.newestGeneration());
    try std.testing.expect(try first.release());
    const recovered = try expectPublished(try publisher.publish(source, 0, null));
    try std.testing.expectEqual(@as(u64, 3), recovered);
    var newest = publisher.borrowNewest().?;
    try std.testing.expectEqual(@as(u21, 'B'), newest.frame.cells[1].codepoint);
    try std.testing.expect(newest.frame.damage.full);
    try std.testing.expect(!try second.release());
    try std.testing.expect(!try newest.release());
}

test "release rejects stale double and unborrowed generations" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 1, 1);
    defer terminal.deinit();
    var publisher = try Publisher.init(std.testing.allocator, std.testing.io, 1, 1);
    defer publisher.deinit();
    const generation = try expectPublished(try publisher.publish(
        terminal.surfaceSnapshot(),
        0,
        null,
    ));
    try std.testing.expectError(error.NotBorrowed, publisher.release(generation));
    var borrowed = publisher.borrowNewest().?;
    try std.testing.expect(!try borrowed.release());
    try std.testing.expectError(error.NotBorrowed, publisher.release(generation));
    try std.testing.expectError(error.StaleGeneration, publisher.release(generation + 1));
}

test "generation exhaustion preserves the last complete publication" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 1, 1);
    defer terminal.deinit();
    var publisher = try Publisher.init(std.testing.allocator, std.testing.io, 1, 1);
    defer publisher.deinit();
    publisher.last_generation = std.math.maxInt(u64) - 1;
    const maximum = try expectPublished(try publisher.publish(
        terminal.surfaceSnapshot(),
        4,
        null,
    ));
    try std.testing.expectEqual(std.math.maxInt(u64), maximum);
    try std.testing.expectError(
        error.GenerationExhausted,
        publisher.publish(terminal.surfaceSnapshot(), 5, null),
    );
    try std.testing.expectEqual(maximum, publisher.newestGeneration());
    var borrowed = publisher.borrowNewest().?;
    try std.testing.expectEqual(@as(u64, 4), borrowed.frame.geometry_generation);
    try std.testing.expect(!try borrowed.release());
}

test "publisher validates bounds and rolls back every allocation" {
    try std.testing.expectError(
        error.InvalidBounds,
        Publisher.init(std.testing.allocator, std.testing.io, 0, 4),
    );
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        initPublisher,
        .{},
    );

    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 2, 2);
    defer terminal.deinit();
    var too_small = try Publisher.init(std.testing.allocator, std.testing.io, 1, 1);
    defer too_small.deinit();
    try std.testing.expectError(
        error.SurfaceBounds,
        too_small.publish(terminal.surfaceSnapshot(), 0, null),
    );
    try std.testing.expectEqual(@as(u64, 0), too_small.newestGeneration());

    var exact = try Publisher.init(std.testing.allocator, std.testing.io, 2, 2);
    defer exact.deinit();
    try std.testing.expectError(
        error.InvalidCellPixels,
        exact.publish(
            terminal.surfaceSnapshot(),
            0,
            .{ .width = 0, .height = 1 },
        ),
    );
    try std.testing.expectEqual(@as(u64, 0), exact.newestGeneration());
}

test "resize preparation rejects borrowed storage without mutation" {
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 1, 2);
    defer terminal.deinit();
    var publisher = try Publisher.init(std.testing.allocator, std.testing.io, 1, 2);
    defer publisher.deinit();
    const generation = try expectPublished(try publisher.publish(
        terminal.surfaceSnapshot(),
        0,
        null,
    ));
    var borrowed = publisher.borrowNewest().?;

    try std.testing.expectError(error.BorrowedFrames, publisher.prepareResize(2, 4));
    try std.testing.expectEqual(@as(u16, 1), publisher.capacity_rows);
    try std.testing.expectEqual(@as(u16, 2), publisher.capacity_cols);
    try std.testing.expectEqual(generation, borrowed.frame.generation);
    try std.testing.expect(!try borrowed.release());
}

test "resize allocation failure preserves ready storage and borrowing" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var terminal = try howl_vt.Terminal.init(std.testing.allocator, 1, 2);
    defer terminal.deinit();
    var publisher = try Publisher.init(failing.allocator(), std.testing.io, 1, 2);
    defer publisher.deinit();
    const generation = try expectPublished(try publisher.publish(
        terminal.surfaceSnapshot(),
        0,
        null,
    ));
    failing.fail_index = failing.alloc_index;

    try std.testing.expectError(error.OutOfMemory, publisher.prepareResize(2, 4));
    try std.testing.expect(failing.has_induced_failure);
    try std.testing.expectEqual(@as(u16, 1), publisher.capacity_rows);
    try std.testing.expectEqual(@as(u16, 2), publisher.capacity_cols);
    var borrowed = publisher.borrowNewest().?;
    try std.testing.expectEqual(generation, borrowed.frame.generation);
    try std.testing.expect(!try borrowed.release());
}

test "resize commit replaces storage at exact geometry in both directions" {
    var publisher = try Publisher.init(std.testing.allocator, std.testing.io, 2, 4);
    defer publisher.deinit();
    var grown = try publisher.prepareResize(4, 8);
    defer grown.deinit();
    grown.commit();
    try std.testing.expectEqual(@as(u16, 4), publisher.capacity_rows);
    try std.testing.expectEqual(@as(u16, 8), publisher.capacity_cols);
    try std.testing.expectEqual(@as(usize, 32), publisher.slots[0].cells.len);

    var shrunk = try publisher.prepareResize(1, 2);
    defer shrunk.deinit();
    shrunk.commit();
    try std.testing.expectEqual(@as(u16, 1), publisher.capacity_rows);
    try std.testing.expectEqual(@as(u16, 2), publisher.capacity_cols);
    try std.testing.expectEqual(@as(usize, 2), publisher.slots[0].cells.len);
    try std.testing.expectEqual(@as(usize, 1), publisher.pending_damage.len);
}

test "resize preparation rolls back every partial allocation" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        preparePublisherResize,
        .{},
    );
}

fn initPublisher(allocator: std.mem.Allocator) !void {
    var publisher = try Publisher.init(allocator, std.testing.io, 4, 8);
    publisher.deinit();
}

fn preparePublisherResize(allocator: std.mem.Allocator) !void {
    var publisher = try Publisher.init(allocator, std.testing.io, 1, 2);
    defer publisher.deinit();
    var prepared = try publisher.prepareResize(4, 8);
    defer prepared.deinit();
}
