//! Compact lazy projected-history ownership for terminal scrollback.

const std = @import("std");
const cell_values = @import("cell.zig");
const scalar_storage = @import("scalar_storage.zig");

const Cell = cell_values.Cell;
const CellAttrs = cell_values.CellAttrs;
const LineGeometry = cell_values.LineGeometry;

const ColdMeta = packed struct(u64) {
    combining_len: u5,
    width: u8,
    height: u8,
    x: u8,
    y: u8,
    subscale_n: u4,
    subscale_d: u4,
    vertical_align: u2,
    horizontal_align: u2,
    semantic_width: bool,
    _padding: u14 = 0,
};

const ColdCell = struct {
    codepoint: u32,
    combining: [3]u32,
    attr_index: u16,
    _attr_padding: u16 = 0,
    tail_start: u32,
    meta: ColdMeta,
};

comptime {
    std.debug.assert(@sizeOf(ColdCell) == 32);
}

fn Stream(comptime T: type, comptime block_items: usize) type {
    return struct {
        const Self = @This();

        const Block = struct {
            previous: ?*Block = null,
            next: ?*Block = null,
            number: u64 = 0,
            items: [block_items]T = undefined,
        };

        const Cursor = struct {
            block: *const Block,
            index: usize,
        };

        const Chain = struct {
            first: ?*Block = null,
            last: ?*Block = null,
            count: usize = 0,

            fn append(self: *Chain, block: *Block) void {
                block.previous = self.last;
                block.next = null;
                if (self.last) |last| {
                    last.next = block;
                } else {
                    self.first = block;
                }
                self.last = block;
                self.count += 1;
            }

            fn takeFirst(self: *Chain) ?*Block {
                const block = self.first orelse return null;
                self.first = block.next;
                if (self.first) |first| {
                    first.previous = null;
                } else {
                    self.last = null;
                }
                block.previous = null;
                block.next = null;
                self.count -= 1;
                return block;
            }
        };

        const Stage = struct {
            blocks: Chain = .{},

            fn deinit(self: *Stage, stream: *Self) void {
                while (self.blocks.takeFirst()) |block| {
                    stream.allocator.destroy(block);
                    stream.allocated_blocks -= 1;
                }
            }
        };

        allocator: std.mem.Allocator,
        max_items: usize,
        head: u64 = 0,
        tail: u64 = 0,
        first: ?*Block = null,
        last: ?*Block = null,
        spare: ?*Block = null,
        allocated_blocks: usize = 0,

        fn init(allocator: std.mem.Allocator, max_items: usize) Self {
            return .{ .allocator = allocator, .max_items = max_items };
        }

        fn deinit(self: *Self) void {
            var block = self.first;
            while (block) |current| {
                block = current.next;
                self.allocator.destroy(current);
            }
            if (self.spare) |spare| self.allocator.destroy(spare);
            self.* = undefined;
        }

        fn len(self: *const Self) usize {
            return @intCast(self.tail - self.head);
        }

        fn blockNumber(position: u64) u64 {
            return position / block_items;
        }

        fn missingBlocksForAppend(self: *const Self, count: usize, pop_count: usize) error{Capacity}!usize {
            if (count == 0) return 0;
            if (count > self.max_items) return error.Capacity;
            const last_position = std.math.add(
                u64,
                self.tail,
                @as(u64, @intCast(count - 1)),
            ) catch return error.Capacity;
            const first_number = blockNumber(self.tail);
            const last_number = blockNumber(last_position);
            const total: usize = @intCast(last_number - first_number + 1);
            // Evicting every item detaches even the block containing the current tail.
            if (pop_count != 0 and pop_count == self.len()) return total;
            const last = self.last orelse return total;
            if (last.number < first_number) return total;
            std.debug.assert(last.number == first_number);
            return @intCast(last_number - last.number);
        }

        fn releasedBlocksForPopFront(self: *const Self, count: usize) usize {
            std.debug.assert(count <= self.len());
            if (count == 0) return 0;
            if (count == self.len()) {
                var all: usize = 0;
                var current = self.first;
                while (current) |block| : (current = block.next) all += 1;
                return all;
            }
            const new_head = self.head + count;
            const release_before = blockNumber(new_head);
            var released: usize = 0;
            var current = self.first;
            while (current) |block| : (current = block.next) {
                if (block.number >= release_before) break;
                released += 1;
            }
            return released;
        }

        fn prepareAppend(
            self: *Self,
            count: usize,
            pop_count: usize,
        ) error{ OutOfMemory, Capacity }!Stage {
            std.debug.assert(pop_count <= self.len());
            const missing = try self.missingBlocksForAppend(count, pop_count);
            const available = self.releasedBlocksForPopFront(pop_count) + @intFromBool(self.spare != null);
            var fresh = missing -| available;
            var stage = Stage{};
            errdefer stage.deinit(self);
            while (fresh != 0) : (fresh -= 1) {
                const block = self.allocator.create(Block) catch return error.OutOfMemory;
                self.allocated_blocks += 1;
                stage.blocks.append(block);
            }
            return stage;
        }

        fn detachFirstBlock(self: *Self) *Block {
            const block = self.first orelse
                // zig-audit: acknowledge panic
                // reason: Stream commit already proved a live block must exist at this boundary.
                @panic("history stream missing live head block");
            self.first = block.next;
            if (self.first) |first| {
                first.previous = null;
            } else {
                self.last = null;
            }
            block.previous = null;
            block.next = null;
            return block;
        }

        fn detachLastBlock(self: *Self) *Block {
            const block = self.last orelse
                // zig-audit: acknowledge panic
                // reason: Stream commit already proved a live block must exist at this boundary.
                @panic("history stream missing live tail block");
            self.last = block.previous;
            if (self.last) |last| {
                last.next = null;
            } else {
                self.first = null;
            }
            block.previous = null;
            block.next = null;
            return block;
        }

        fn popFrontPrepared(self: *Self, count: usize) Chain {
            std.debug.assert(count <= self.len());
            var recycled = Chain{};
            if (count == 0) return recycled;
            const new_head = self.head + count;
            if (count == self.len()) {
                while (self.first != null) recycled.append(self.detachFirstBlock());
                self.head = new_head;
                return recycled;
            }
            const release_before = blockNumber(new_head);
            while (self.first) |first| {
                if (first.number >= release_before) break;
                recycled.append(self.detachFirstBlock());
            }
            self.head = new_head;
            return recycled;
        }

        fn keepOrFree(self: *Self, chain: *Chain) void {
            if (self.spare == null) self.spare = chain.takeFirst();
            while (chain.takeFirst()) |block| {
                self.allocator.destroy(block);
                self.allocated_blocks -= 1;
            }
        }

        fn takePreparedBlock(
            self: *Self,
            recycled: *Chain,
            stage: *Stage,
        ) *Block {
            if (self.spare) |block| {
                self.spare = null;
                block.previous = null;
                block.next = null;
                return block;
            }
            if (recycled.takeFirst()) |block| return block;
            if (stage.blocks.takeFirst()) |block| return block;
            // zig-audit: acknowledge panic
            // reason: Prepared admission proves every future tail block before retained history mutates.
            @panic("history stream prepared block deficit");
        }

        fn ensureTailBlockPrepared(
            self: *Self,
            recycled: *Chain,
            stage: *Stage,
        ) *Block {
            const number = blockNumber(self.tail);
            if (self.last) |last| {
                if (last.number == number) return last;
                std.debug.assert(last.number < number);
            }
            const block = self.takePreparedBlock(recycled, stage);
            block.number = number;
            block.previous = self.last;
            block.next = null;
            if (self.last) |last| {
                last.next = block;
            } else {
                self.first = block;
            }
            self.last = block;
            return block;
        }

        fn cursorForAppendPrepared(
            self: *Self,
            recycled: *Chain,
            stage: *Stage,
        ) Cursor {
            const block = self.ensureTailBlockPrepared(recycled, stage);
            return .{
                .block = block,
                .index = @intCast(self.tail % block_items),
            };
        }

        fn writableTailPrepared(
            self: *Self,
            recycled: *Chain,
            stage: *Stage,
            count: usize,
        ) []T {
            std.debug.assert(count != 0 and count <= self.max_items - self.len());
            const block = self.ensureTailBlockPrepared(recycled, stage);
            const index: usize = @intCast(self.tail % block_items);
            return block.items[index..][0..@min(count, block_items - index)];
        }

        fn advanceTailPrepared(self: *Self, count: usize) void {
            std.debug.assert(count != 0 and count <= self.max_items - self.len());
            std.debug.assert(count <= block_items - self.tail % block_items);
            self.tail += count;
        }

        fn appendPrepared(
            self: *Self,
            recycled: *Chain,
            stage: *Stage,
            value: T,
        ) void {
            std.debug.assert(self.len() < self.max_items);
            const block = self.ensureTailBlockPrepared(recycled, stage);
            block.items[@intCast(self.tail % block_items)] = value;
            self.tail += 1;
        }

        fn atCursor(_: *const Self, start: Cursor, offset: usize) *const T {
            var block = start.block;
            var index = start.index + offset;
            while (index >= block_items) {
                index -= block_items;
                block = block.next orelse
                    // zig-audit: acknowledge panic
                    // reason: Accepted row descriptors only name payload still owned by the linked stream.
                    @panic("history stream cursor escaped retained payload");
            }
            return &block.items[index];
        }

        fn popBack(self: *Self, count: usize) void {
            std.debug.assert(count <= self.len());
            if (count == 0) return;
            const new_tail = self.tail - count;
            if (count == self.len()) {
                var released = Chain{};
                while (self.last != null) released.append(self.detachLastBlock());
                self.tail = new_tail;
                self.keepOrFree(&released);
                return;
            }
            const keep_number = blockNumber(new_tail);
            var released = Chain{};
            while (self.last) |last| {
                const detach = last.number > keep_number or
                    (last.number == keep_number and new_tail % block_items == 0);
                if (!detach) break;
                released.append(self.detachLastBlock());
            }
            self.tail = new_tail;
            self.keepOrFree(&released);
        }

        fn discardStage(self: *Self, stage: *Stage) void {
            stage.deinit(self);
        }

        fn finishCommit(
            self: *Self,
            recycled: *Chain,
            stage: *Stage,
        ) void {
            self.keepOrFree(recycled);
            self.keepOrFree(&stage.blocks);
        }
    };
}

const CellStream = Stream(ColdCell, 2048);
const AttrStream = Stream(CellAttrs, 1024);
const ScalarStream = Stream(u32, 16384);

const Row = struct {
    cell_start: ?CellStream.Cursor,
    attr_start: ?AttrStream.Cursor,
    scalar_start: ?ScalarStream.Cursor,
    scalar_count: u32,
    cell_count: u16,
    attr_count: u16,
    wrapped: bool,
    geometry: LineGeometry,
};

const Shape = struct {
    cells: u16,
    attrs: u16,
    scalars: u32,
};

const Recycled = struct {
    cells: CellStream.Chain = .{},
    attrs: AttrStream.Chain = .{},
    scalars: ScalarStream.Chain = .{},
};

/// One immutable hot-row source admitted into projected history.
pub const Source = struct {
    cells: []const Cell,
    scalars: *const scalar_storage.Storage,
    scalar_start: usize,
    wrapped: bool,
    geometry: LineGeometry,
};

/// Failure while validating or staging one projected-history row.
pub const PrepareError = error{
    OutOfMemory,
    Capacity,
    InvalidSource,
};

/// Compact lazy projected-history owner.
pub const Store = struct {
    /// Prepared admission transaction. Discard it if commit will not run.
    pub const Prepared = struct {
        source: Source,
        shape: Shape,
        drop_oldest: bool,
        cell_stage: CellStream.Stage,
        attr_stage: AttrStream.Stage,
        scalar_stage: ScalarStream.Stage,
        consumed: bool = false,

        /// Reports whether committing this row will evict the current oldest row.
        pub fn dropsOldest(self: *const Prepared) bool {
            return self.drop_oldest;
        }
    };

    allocator: std.mem.Allocator,
    columns: u16,
    rows: []Row,
    row_head: usize = 0,
    row_count: usize = 0,
    row_base: u32 = 0,
    cells: CellStream,
    attrs: AttrStream,
    scalars: ScalarStream,

    /// Initializes an empty bounded projected-history store without payload blocks.
    pub fn init(
        allocator: std.mem.Allocator,
        row_capacity: u16,
        columns: u16,
        row_base: u32,
    ) error{OutOfMemory}!Store {
        const max_cells = std.math.mul(usize, row_capacity, columns) catch
            return error.OutOfMemory;
        const rows = allocator.alloc(Row, row_capacity) catch return error.OutOfMemory;
        const page_count = std.math.divCeil(
            usize,
            max_cells,
            scalar_storage.page_cells,
        ) catch {
            allocator.free(rows);
            return error.OutOfMemory;
        };
        const max_scalars = std.math.mul(
            usize,
            page_count,
            scalar_storage.scalar_slots,
        ) catch {
            allocator.free(rows);
            return error.OutOfMemory;
        };
        return .{
            .allocator = allocator,
            .columns = columns,
            .rows = rows,
            .row_base = row_base,
            .cells = CellStream.init(allocator, max_cells),
            .attrs = AttrStream.init(allocator, max_cells),
            .scalars = ScalarStream.init(allocator, max_scalars),
        };
    }

    /// Releases every retained payload block and descriptor.
    pub fn deinit(self: *Store) void {
        self.scalars.deinit();
        self.attrs.deinit();
        self.cells.deinit();
        self.allocator.free(self.rows);
        self.* = undefined;
    }

    /// Returns configured projected-row capacity.
    pub fn capacity(self: *const Store) u16 {
        return @intCast(self.rows.len);
    }

    /// Returns the number of retained projected rows.
    pub fn count(self: *const Store) u32 {
        return @intCast(self.row_count);
    }

    /// Returns the absolute identity of the oldest retained projected row.
    pub fn base(self: *const Store) u32 {
        return self.row_base;
    }

    fn semanticColumns(self: *const Store, geometry: LineGeometry) u16 {
        return switch (geometry) {
            .single_width => self.columns,
            .double_width, .double_height_top, .double_height_bottom => @max(@as(u16, 1), self.columns / 2),
        };
    }

    fn rowAtLogical(self: *const Store, logical: usize) *const Row {
        std.debug.assert(logical < self.row_count);
        return &self.rows[(self.row_head + logical) % self.rows.len];
    }

    fn logicalForRecency(self: *const Store, recency: u32) ?usize {
        if (recency >= self.row_count) return null;
        return self.row_count - 1 - @as(usize, recency);
    }

    fn shape(self: *const Store, source: Source) PrepareError!Shape {
        if (source.cells.len > self.semanticColumns(source.geometry) or
            source.cells.len > std.math.maxInt(u16) or
            source.scalar_start > source.scalars.cellCapacity() or
            source.cells.len > source.scalars.cellCapacity() - source.scalar_start)
            return error.InvalidSource;

        var attrs: usize = 0;
        var scalars: usize = 0;
        var previous: ?*const CellAttrs = null;
        for (source.cells, 0..) |*value, column| {
            if (previous == null or !cell_values.attrsEqual(previous.?, &value.attrs)) {
                attrs += 1;
                previous = &value.attrs;
            }
            const tail = source.scalars.tail(
                source.scalar_start + column,
                value.combining_len,
            ) catch return error.InvalidSource;
            scalars = std.math.add(usize, scalars, tail.len) catch
                return error.Capacity;
        }
        if (attrs > std.math.maxInt(u16) or scalars > std.math.maxInt(u32))
            return error.Capacity;
        return .{
            .cells = @intCast(source.cells.len),
            .attrs = @intCast(attrs),
            .scalars = @intCast(scalars),
        };
    }

    fn canAppend(self: *const Store, shape_value: Shape, drop_oldest: bool) bool {
        var cells_after = self.cells.len();
        var attrs_after = self.attrs.len();
        var scalars_after = self.scalars.len();
        if (drop_oldest) {
            const outgoing = self.rowAtLogical(0);
            cells_after -= outgoing.cell_count;
            attrs_after -= outgoing.attr_count;
            scalars_after -= outgoing.scalar_count;
        }
        return cells_after + shape_value.cells <= self.cells.max_items and
            attrs_after + shape_value.attrs <= self.attrs.max_items and
            scalars_after + shape_value.scalars <= self.scalars.max_items;
    }

    /// Stages every resource required to append one row without mutating retained history.
    pub fn preparePush(self: *Store, source: Source) PrepareError!Prepared {
        if (self.rows.len == 0) return error.Capacity;
        const shape_value = try self.shape(source);
        const drop_oldest = self.row_count == self.rows.len;
        if (!self.canAppend(shape_value, drop_oldest)) return error.Capacity;

        const outgoing = if (drop_oldest) self.rowAtLogical(0) else null;
        var cell_stage = try self.cells.prepareAppend(shape_value.cells, if (outgoing) |row| row.cell_count else 0);
        errdefer self.cells.discardStage(&cell_stage);
        var attr_stage = try self.attrs.prepareAppend(shape_value.attrs, if (outgoing) |row| row.attr_count else 0);
        errdefer self.attrs.discardStage(&attr_stage);
        var scalar_stage = try self.scalars.prepareAppend(shape_value.scalars, if (outgoing) |row| row.scalar_count else 0);
        errdefer self.scalars.discardStage(&scalar_stage);

        return .{
            .source = source,
            .shape = shape_value,
            .drop_oldest = drop_oldest,
            .cell_stage = cell_stage,
            .attr_stage = attr_stage,
            .scalar_stage = scalar_stage,
        };
    }

    /// Releases fresh blocks held by an uncommitted prepared row.
    pub fn discardPrepared(self: *Store, prepared: *Prepared) void {
        if (prepared.consumed) return;
        self.scalars.discardStage(&prepared.scalar_stage);
        self.attrs.discardStage(&prepared.attr_stage);
        self.cells.discardStage(&prepared.cell_stage);
        prepared.consumed = true;
    }

    fn advanceBase(self: *Store, count_value: u32) void {
        self.row_base = std.math.add(u32, self.row_base, count_value) catch
            // zig-audit: acknowledge panic
            // reason: Projected row identity is deliberately non-wrapping for one terminal lifetime.
            @panic("terminal history row identity exhausted");
    }

    fn detachOldestForCommit(self: *Store) Recycled {
        const row = self.rowAtLogical(0).*;
        const cell_recycled = self.cells.popFrontPrepared(row.cell_count);
        const attr_recycled = self.attrs.popFrontPrepared(row.attr_count);
        const scalar_recycled = self.scalars.popFrontPrepared(row.scalar_count);
        self.row_head = (self.row_head + 1) % self.rows.len;
        self.row_count -= 1;
        self.advanceBase(1);
        return .{
            .cells = cell_recycled,
            .attrs = attr_recycled,
            .scalars = scalar_recycled,
        };
    }

    /// Commits one fully prepared row allocation-free and infallibly.
    pub fn commitPush(self: *Store, prepared: *Prepared) void {
        std.debug.assert(!prepared.consumed);
        var recycled = if (prepared.drop_oldest)
            self.detachOldestForCommit()
        else
            Recycled{};

        const row_slot = (self.row_head + self.row_count) % self.rows.len;
        const cell_start = if (prepared.shape.cells != 0)
            self.cells.cursorForAppendPrepared(&recycled.cells, &prepared.cell_stage)
        else
            null;
        const attr_start = if (prepared.shape.attrs != 0)
            self.attrs.cursorForAppendPrepared(&recycled.attrs, &prepared.attr_stage)
        else
            null;
        const scalar_start = if (prepared.shape.scalars != 0)
            self.scalars.cursorForAppendPrepared(&recycled.scalars, &prepared.scalar_stage)
        else
            null;

        var previous: ?*const CellAttrs = null;
        var current_attr: u16 = 0;
        var encoded_attrs: u16 = 0;
        var encoded_scalars: u32 = 0;
        // Preparation proved these facts for the immutable borrowed row.
        const uniform_attrs = prepared.shape.attrs == 1;
        const no_tails = prepared.shape.scalars == 0;
        if (uniform_attrs) {
            self.attrs.appendPrepared(&recycled.attrs, &prepared.attr_stage, prepared.source.cells[0].attrs);
            encoded_attrs = 1;
        }
        var column: usize = 0;
        while (column < prepared.source.cells.len) {
            const destination = self.cells.writableTailPrepared(
                &recycled.cells,
                &prepared.cell_stage,
                prepared.source.cells.len - column,
            );
            for (destination, prepared.source.cells[column..][0..destination.len], 0..) |*cold, *value, offset| {
                if (!uniform_attrs and (previous == null or !cell_values.attrsEqual(previous.?, &value.attrs))) {
                    current_attr = encoded_attrs;
                    self.attrs.appendPrepared(
                        &recycled.attrs,
                        &prepared.attr_stage,
                        value.attrs,
                    );
                    encoded_attrs += 1;
                    previous = &value.attrs;
                }

                const tail_start = encoded_scalars;
                const tail = if (no_tails) &.{} else prepared.source.scalars.tail(
                    prepared.source.scalar_start + column + offset,
                    value.combining_len,
                ) catch
                    // zig-audit: acknowledge panic
                    // reason: Prepared admission validated this unchanged borrowed scalar source before commit.
                    @panic("prepared history scalar source changed before commit");
                for (tail) |scalar| {
                    self.scalars.appendPrepared(
                        &recycled.scalars,
                        &prepared.scalar_stage,
                        scalar,
                    );
                    encoded_scalars += 1;
                }

                cold.* = .{
                    .codepoint = value.codepoint,
                    .combining = value.combining,
                    .attr_index = current_attr,
                    .tail_start = tail_start,
                    .meta = .{
                        .combining_len = @intCast(value.combining_len),
                        .width = value.width,
                        .height = value.height,
                        .x = value.x,
                        .y = value.y,
                        .subscale_n = value.subscale_n,
                        .subscale_d = value.subscale_d,
                        .vertical_align = value.vertical_align,
                        .horizontal_align = value.horizontal_align,
                        .semantic_width = value.semantic_width,
                    },
                };
            }
            self.cells.advanceTailPrepared(destination.len);
            column += destination.len;
        }
        std.debug.assert(encoded_attrs == prepared.shape.attrs);
        std.debug.assert(encoded_scalars == prepared.shape.scalars);

        self.rows[row_slot] = .{
            .cell_start = cell_start,
            .attr_start = attr_start,
            .scalar_start = scalar_start,
            .scalar_count = prepared.shape.scalars,
            .cell_count = prepared.shape.cells,
            .attr_count = prepared.shape.attrs,
            .wrapped = prepared.source.wrapped,
            .geometry = prepared.source.geometry,
        };
        self.row_count += 1;

        self.cells.finishCommit(&recycled.cells, &prepared.cell_stage);
        self.attrs.finishCommit(&recycled.attrs, &prepared.attr_stage);
        self.scalars.finishCommit(&recycled.scalars, &prepared.scalar_stage);
        prepared.consumed = true;
    }

    fn decodedCell(self: *const Store, row: *const Row, column: u16) Cell {
        if (column >= row.cell_count) return cell_values.blank;
        const cell_start = row.cell_start orelse
            // zig-audit: acknowledge panic
            // reason: A nonempty accepted row always publishes its cell cursor with the descriptor.
            @panic("history row missing cell cursor");
        const cold = self.cells.atCursor(cell_start, column).*;
        const attr_start = row.attr_start orelse
            // zig-audit: acknowledge panic
            // reason: Every nonempty accepted row owns at least one exact attribute run.
            @panic("history row missing attribute cursor");
        const attrs = self.attrs.atCursor(attr_start, cold.attr_index).*;
        return .{
            .codepoint = cold.codepoint,
            .combining_len = @intCast(cold.meta.combining_len),
            .combining = cold.combining,
            .width = cold.meta.width,
            .height = cold.meta.height,
            .x = cold.meta.x,
            .y = cold.meta.y,
            .subscale_n = cold.meta.subscale_n,
            .subscale_d = cold.meta.subscale_d,
            .vertical_align = cold.meta.vertical_align,
            .horizontal_align = cold.meta.horizontal_align,
            .semantic_width = cold.meta.semantic_width,
            .attrs = attrs,
        };
    }

    /// Returns a copied history cell by oldest-first row index.
    pub fn cellAtLogical(self: *const Store, logical: u32, column: u16) Cell {
        if (logical >= self.row_count or column >= self.columns) return cell_values.blank;
        return self.decodedCell(self.rowAtLogical(logical), column);
    }

    /// Returns a copied history cell by newest-first recency.
    pub fn cellAtRecency(self: *const Store, recency: u32, column: u16) Cell {
        const logical = self.logicalForRecency(recency) orelse return cell_values.blank;
        if (column >= self.columns) return cell_values.blank;
        return self.decodedCell(self.rowAtLogical(logical), column);
    }

    fn scalarsAtLogicalInternal(
        self: *const Store,
        logical: usize,
        column: u16,
        output: *[scalar_storage.maximum_scalars]u32,
    ) []const u32 {
        if (logical >= self.row_count or column >= self.columns) return &.{};
        const observed = self.decodedCell(self.rowAtLogical(logical), column);
        if (observed.x > column or observed.y > logical) return &.{};
        const lead_logical = logical - observed.y;
        const lead_column = column - observed.x;
        const row = self.rowAtLogical(lead_logical);
        if (lead_column >= row.cell_count) return &.{};
        const cell_start = row.cell_start orelse return &.{};
        const cold = self.cells.atCursor(cell_start, lead_column).*;
        if (cold.codepoint == 0) return &.{};

        output[0] = cold.codepoint;
        const direct = @min(
            @as(usize, cold.meta.combining_len),
            cold.combining.len,
        );
        @memcpy(output[1..][0..direct], cold.combining[0..direct]);
        const tail_len = @as(usize, cold.meta.combining_len) - direct;
        if (tail_len != 0) {
            const scalar_start = row.scalar_start orelse
                // zig-audit: acknowledge panic
                // reason: A row with external scalars publishes its scalar cursor atomically with the descriptor.
                @panic("history row missing scalar cursor");
            var index: usize = 0;
            while (index < tail_len) : (index += 1) {
                const output_index: usize = @as(usize, 1) + direct + index;
                output[output_index] = self.scalars.atCursor(
                    scalar_start,
                    @as(usize, cold.tail_start) + index,
                ).*;
            }
        }
        return output[0 .. 1 + @as(usize, cold.meta.combining_len)];
    }

    /// Copies one complete lead-cell scalar sequence by oldest-first row index.
    pub fn scalarsAtLogical(
        self: *const Store,
        logical: u32,
        column: u16,
        output: *[scalar_storage.maximum_scalars]u32,
    ) []const u32 {
        return self.scalarsAtLogicalInternal(logical, column, output);
    }

    /// Copies one complete lead-cell scalar sequence by newest-first recency.
    pub fn scalarsAtRecency(
        self: *const Store,
        recency: u32,
        column: u16,
        output: *[scalar_storage.maximum_scalars]u32,
    ) []const u32 {
        const logical = self.logicalForRecency(recency) orelse return &.{};
        return self.scalarsAtLogicalInternal(logical, column, output);
    }

    /// Returns retained row content length by oldest-first index.
    pub fn contentLengthLogical(self: *const Store, logical: u32) u16 {
        if (logical >= self.row_count) return 0;
        return self.rowAtLogical(logical).cell_count;
    }

    /// Returns retained row wrap state by newest-first recency.
    pub fn wrappedRecency(self: *const Store, recency: u32) bool {
        const logical = self.logicalForRecency(recency) orelse return false;
        return self.rowAtLogical(logical).wrapped;
    }

    /// Returns retained row geometry by newest-first recency.
    pub fn geometryRecency(self: *const Store, recency: u32) LineGeometry {
        const logical = self.logicalForRecency(recency) orelse return .single_width;
        return self.rowAtLogical(logical).geometry;
    }

    /// Returns retained row wrap state by oldest-first index.
    pub fn wrappedLogical(self: *const Store, logical: u32) bool {
        if (logical >= self.row_count) return false;
        return self.rowAtLogical(logical).wrapped;
    }

    /// Returns retained row geometry by oldest-first index.
    pub fn geometryLogical(self: *const Store, logical: u32) LineGeometry {
        if (logical >= self.row_count) return .single_width;
        return self.rowAtLogical(logical).geometry;
    }

    /// Drops oldest retained rows and advances projected-row identity.
    pub fn dropOldest(self: *Store, requested: u32) void {
        var remaining = @min(requested, self.count());
        while (remaining != 0) : (remaining -= 1) {
            var recycled = self.detachOldestForCommit();
            self.cells.keepOrFree(&recycled.cells);
            self.attrs.keepOrFree(&recycled.attrs);
            self.scalars.keepOrFree(&recycled.scalars);
        }
    }

    /// Removes the newest retained row without advancing the oldest identity.
    pub fn popNewest(self: *Store) void {
        if (self.row_count == 0) return;
        const row = self.rowAtLogical(self.row_count - 1).*;
        self.cells.popBack(row.cell_count);
        self.attrs.popBack(row.attr_count);
        self.scalars.popBack(row.scalar_count);
        self.row_count -= 1;
    }
};

fn testSource(
    allocator: std.mem.Allocator,
    cells: []Cell,
) !scalar_storage.Storage {
    var storage = try scalar_storage.Storage.init(allocator, cells.len);
    errdefer storage.deinit();
    for (cells, 0..) |*value, index| {
        if (index % 3 != 0) continue;
        value.codepoint = @intCast('A' + index % 26);
        value.combining_len = 6;
        value.combining = .{ 0x301, 0x302, 0x303 };
        try storage.set(index, 0, &.{ 0x304, 0x305, 0x306 });
    }
    return storage;
}

test "history store round trips exact cells scalars and implicit blanks" {
    var cells: [8]Cell = @splat(cell_values.blank);
    var source_scalars = try testSource(std.testing.allocator, &cells);
    defer source_scalars.deinit();
    cells[0].attrs.bold = true;
    cells[1].attrs.bg = cell_values.Color.rgbComponents(10, 20, 30);

    var store = try Store.init(std.testing.allocator, 4, 12, 7);
    defer store.deinit();
    var prepared = try store.preparePush(.{
        .cells = cells[0..8],
        .scalars = &source_scalars,
        .scalar_start = 0,
        .wrapped = false,
        .geometry = .single_width,
    });
    store.commitPush(&prepared);

    try std.testing.expectEqual(@as(u32, 1), store.count());
    try std.testing.expectEqual(@as(u32, 7), store.base());
    for (cells, 0..) |expected, column|
        try std.testing.expectEqualDeep(expected, store.cellAtLogical(0, @intCast(column)));
    try std.testing.expectEqualDeep(cell_values.blank, store.cellAtLogical(0, 11));

    var expected_scalars: [scalar_storage.maximum_scalars]u32 = undefined;
    var actual_scalars: [scalar_storage.maximum_scalars]u32 = undefined;
    const expected_tail = try source_scalars.tail(0, cells[0].combining_len);
    expected_scalars[0] = cells[0].codepoint;
    @memcpy(expected_scalars[1..4], &cells[0].combining);
    @memcpy(expected_scalars[4..][0..expected_tail.len], expected_tail);
    const actual = store.scalarsAtLogical(0, 0, &actual_scalars);
    try std.testing.expectEqualSlices(
        u32,
        expected_scalars[0 .. 4 + expected_tail.len],
        actual,
    );
}

test "history store evicts oldest transactionally and preserves row identity" {
    var cells: [2]Cell = @splat(cell_values.blank);
    var scalars = try scalar_storage.Storage.init(std.testing.allocator, cells.len);
    defer scalars.deinit();
    var store = try Store.init(std.testing.allocator, 2, 2, 40);
    defer store.deinit();

    for (0..3) |index| {
        cells[0].codepoint = @intCast('A' + index);
        var prepared = try store.preparePush(.{
            .cells = cells[0..1],
            .scalars = &scalars,
            .scalar_start = 0,
            .wrapped = false,
            .geometry = .single_width,
        });
        if (index < 2)
            try std.testing.expect(!prepared.dropsOldest())
        else
            try std.testing.expect(prepared.dropsOldest());
        store.commitPush(&prepared);
    }

    try std.testing.expectEqual(@as(u32, 2), store.count());
    try std.testing.expectEqual(@as(u32, 41), store.base());
    try std.testing.expectEqual(@as(u32, 'B'), store.cellAtLogical(0, 0).codepoint);
    try std.testing.expectEqual(@as(u32, 'C'), store.cellAtRecency(0, 0).codepoint);
    store.popNewest();
    try std.testing.expectEqual(@as(u32, 1), store.count());
    try std.testing.expectEqual(@as(u32, 41), store.base());
}

test "history store empty normalization retains at most one block per stream" {
    const cells = try std.testing.allocator.alloc(Cell, 2048);
    defer std.testing.allocator.free(cells);
    @memset(cells, cell_values.blank);
    for (cells, 0..) |*value, index| {
        value.codepoint = 'x';
        if (index % 2 == 0) value.attrs.bold = true;
    }
    var scalars = try scalar_storage.Storage.init(std.testing.allocator, cells.len);
    defer scalars.deinit();

    var store = try Store.init(std.testing.allocator, 2, 2048, 0);
    defer store.deinit();
    var prepared = try store.preparePush(.{
        .cells = cells,
        .scalars = &scalars,
        .scalar_start = 0,
        .wrapped = false,
        .geometry = .single_width,
    });
    store.commitPush(&prepared);
    try std.testing.expect(store.cells.allocated_blocks >= 1);
    try std.testing.expect(store.attrs.allocated_blocks >= 1);

    store.popNewest();
    try std.testing.expectEqual(@as(u32, 0), store.count());
    try std.testing.expect(store.cells.allocated_blocks <= 1);
    try std.testing.expect(store.attrs.allocated_blocks <= 1);
    try std.testing.expect(store.scalars.allocated_blocks <= 1);
}

test "history store prepared allocation failure leaves accepted rows unchanged" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const cells = try std.testing.allocator.alloc(Cell, 2048);
    defer std.testing.allocator.free(cells);
    @memset(cells, cell_values.blank);
    cells[0].codepoint = 'A';
    var source_scalars = try scalar_storage.Storage.init(std.testing.allocator, cells.len);
    defer source_scalars.deinit();

    var store = try Store.init(failing.allocator(), 2, 2048, 9);
    defer store.deinit();
    var first = try store.preparePush(.{
        .cells = cells,
        .scalars = &source_scalars,
        .scalar_start = 0,
        .wrapped = false,
        .geometry = .single_width,
    });
    store.commitPush(&first);
    const before_count = store.count();
    const before_base = store.base();
    const before_cell = store.cellAtLogical(0, 0);

    cells[0].attrs.bold = true;
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, store.preparePush(.{
        .cells = cells[0..1],
        .scalars = &source_scalars,
        .scalar_start = 0,
        .wrapped = true,
        .geometry = .single_width,
    }));
    failing.fail_index = std.math.maxInt(usize);

    try std.testing.expectEqual(before_count, store.count());
    try std.testing.expectEqual(before_base, store.base());
    try std.testing.expectEqualDeep(before_cell, store.cellAtLogical(0, 0));
}

test "history store uniform attributes preserve inline scalars and validate admission" {
    var cells: [4]Cell = @splat(cell_values.blank);
    for (&cells, 0..) |*value, index| {
        value.codepoint = @intCast('A' + index);
        value.attrs.bold = true;
        value.attrs.bg = cell_values.Color.rgbComponents(10, 20, 30);
        value.combining_len = @intCast(index);
        value.combining = .{ 0x301, 0x302, 0x303 };
    }
    var scalars = try scalar_storage.Storage.init(std.testing.allocator, cells.len);
    defer scalars.deinit();
    var store = try Store.init(std.testing.allocator, 2, 4, 10);
    defer store.deinit();
    const source = Source{ .cells = &cells, .scalars = &scalars, .scalar_start = 0, .wrapped = true, .geometry = .single_width };
    var prepared = try store.preparePush(source);
    store.commitPush(&prepared);
    for (cells, 0..) |expected, column| {
        try std.testing.expectEqualDeep(expected, store.cellAtLogical(0, @intCast(column)));
        var output: [scalar_storage.maximum_scalars]u32 = undefined;
        const actual = store.scalarsAtLogical(0, @intCast(column), &output);
        try std.testing.expectEqual(expected.codepoint, actual[0]);
        try std.testing.expectEqualSlices(u32, expected.combining[0..expected.combining_len], actual[1..]);
    }
    try scalars.set(0, 0, &.{0x304});
    try std.testing.expectError(error.InvalidSource, store.preparePush(source));
    try std.testing.expectEqual(@as(u32, 1), store.count());
    try std.testing.expectEqual(@as(u32, 10), store.base());
    for (cells, 0..) |expected, column|
        try std.testing.expectEqualDeep(expected, store.cellAtLogical(0, @intCast(column)));
}

test "history store bulk cell spans preserve block crossings and evicted row payloads" {
    const cells = try std.testing.allocator.alloc(Cell, 2053);
    defer std.testing.allocator.free(cells);
    @memset(cells, cell_values.blank);
    var scalars = try scalar_storage.Storage.init(std.testing.allocator, cells.len);
    defer scalars.deinit();
    for (cells, 0..) |*value, index| {
        value.codepoint = 'x';
        value.attrs.bg = .indexed(@intCast(index % 7));
        if (index % 8 == 0) {
            value.combining_len = 6;
            value.combining = .{ 0x301, 0x302, 0x303 };
            try scalars.set(index, 0, &.{ 0x304, 0x305, 0x306 });
        }
    }
    var store = try Store.init(std.testing.allocator, 3, @intCast(cells.len), 0);
    defer store.deinit();
    for (0..9) |sequence| {
        cells[0].codepoint = @intCast('A' + sequence);
        var prepared = try store.preparePush(.{ .cells = cells, .scalars = &scalars, .scalar_start = 0, .wrapped = false, .geometry = .single_width });
        store.commitPush(&prepared);
        const newest = store.count() - 1;
        for (cells, 0..) |expected, column|
            try std.testing.expectEqualDeep(expected, store.cellAtLogical(newest, @intCast(column)));
        for (0..store.count()) |logical|
            try std.testing.expectEqual(@as(u32, 'A') + store.base() + @as(u32, @intCast(logical)), store.cellAtLogical(@intCast(logical), 0).codepoint);
        var output: [scalar_storage.maximum_scalars]u32 = undefined;
        const actual = store.scalarsAtLogical(newest, 2048, &output);
        try std.testing.expectEqualSlices(u32, &.{ 'x', 0x301, 0x302, 0x303, 0x304, 0x305, 0x306 }, actual);
    }
    try std.testing.expectEqual(@as(u32, 3), store.count());
    try std.testing.expectEqual(@as(u32, 6), store.base());
}

test "history capacity one prepares detached tail blocks before eviction and preserves allocation failure" {
    var cells: [80]Cell = @splat(cell_values.blank);
    for (&cells, 0..) |*value, index| {
        value.codepoint = 'x';
        value.attrs.bg = .indexed(@intCast(index % 3));
    }
    var scalars = try scalar_storage.Storage.init(std.testing.allocator, cells.len);
    defer scalars.deinit();
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    var store = try Store.init(failing.allocator(), 1, 80, 0);
    defer store.deinit();
    const source = Source{ .cells = &cells, .scalars = &scalars, .scalar_start = 0, .wrapped = false, .geometry = .single_width };
    for (0..12) |_| {
        var prepared = try store.preparePush(source);
        store.commitPush(&prepared);
    }
    const before_base = store.base();
    cells[0].codepoint = 'A';
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, store.preparePush(source));
    try std.testing.expectEqual(@as(u32, 1), store.count());
    try std.testing.expectEqual(before_base, store.base());
    try std.testing.expectEqual(@as(u32, 'x'), store.cellAtLogical(0, 0).codepoint);
    failing.fail_index = std.math.maxInt(usize);
    for (0..64) |sequence| {
        cells[0].codepoint = @intCast('A' + sequence % 26);
        var prepared = try store.preparePush(source);
        store.commitPush(&prepared);
        for (cells, 0..) |expected, column|
            try std.testing.expectEqualDeep(expected, store.cellAtLogical(0, @intCast(column)));
        try std.testing.expectEqual(@as(u32, 1), store.count());
        try std.testing.expectEqual(before_base + 1 + @as(u32, @intCast(sequence)), store.base());
    }
}
