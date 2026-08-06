//! Owns one atomic, backend-neutral visual transaction emitted by VT.
//!
//! Operations contain final resolved cells and colors. Palette, protection,
//! wide-cell, and parser semantics remain in VT. Slices borrow transaction-owned
//! storage and remain valid until `Transaction.deinit` transfers or frees it.

const std = @import("std");

/// Bounds one active terminal grid independently of its dimensions.
pub const maximum_cells: usize = 65_536;
/// Bounds three one-byte color-channel classifications for every active cell.
pub const recolor_classification_bytes: usize = maximum_cells * 3;
/// Bounds one transaction-local table of final resolved RGB values.
pub const recolor_rgb_bytes: usize = 256 * 3;
/// Retains ordinary parser-byte operation ownership without allocation.
pub const inline_operation_capacity: usize = 32;
/// Retains ordinary parser-byte resolved cells without allocation.
pub const inline_cell_capacity: usize = 32;

/// Stores one final resolved eight-bit color.
pub const Rgb = extern struct { r: u8, g: u8, b: u8 };

/// Stores only visual style bits consumed by the terminal renderer.
pub const Style = packed struct(u8) {
    bold: bool = false,
    dim: bool = false,
    italic: bool = false,
    underline: bool = false,
    strikethrough: bool = false,
    reserved: u3 = 0,
};

/// Stores one final blank or ASCII cell without VT provenance.
pub const Cell = extern struct {
    codepoint: u8,
    foreground: Rgb,
    background: Rgb,
    underline_color: Rgb,
    style: Style = .{},
};

/// Identifies one nonempty terminal-cell rectangle.
pub const Rect = extern struct { row: u16, col: u16, rows: u16, cols: u16 };
/// Selects one static cursor shape or hidden state.
pub const CursorShape = enum(u8) { block, underline, bar, hidden };

/// Stores one final static cursor presentation.
pub const Cursor = extern struct {
    row: u16 = 0,
    col: u16 = 0,
    color: Rgb = .{ .r = 0, .g = 0, .b = 0 },
    text_color: Rgb = .{ .r = 0, .g = 0, .b = 0 },
    shape: CursorShape = .hidden,
    visible: bool = false,
};

/// Identifies the finite semantic cause of a complete grid replacement.
pub const ReplacementKind = enum(u8) { initialization, resize, alternate };

/// Selects final RGB replacements through three per-cell token arrays.
pub const Recolor = struct {
    foreground: []const u8,
    background: []const u8,
    underline: []const u8,
    rgb: *const [256]Rgb,
};

/// Applies only final visual field operations selected by VT.
pub const VisualPatch = struct {
    rect: Rect,
    changed_mask: ?[]const u8,
    set_style: Style = .{},
    clear_style: Style = .{},
    toggle_style: Style = .{},
    swap_foreground_background: bool = false,
    foreground: ?Rgb = null,
    background: ?Rgb = null,
    underline: ?Rgb = null,
};

/// Carries one ordered backend-neutral visual mutation.
pub const Operation = union(enum) {
    set_cells: struct { row: u16, col: u16, cells: []const Cell },
    fill: struct { rect: Rect, cell: Cell },
    copy: struct { source: Rect, destination_row: u16, destination_col: u16 },
    masked_fill: struct { rect: Rect, mask: []const u8, cell: Cell },
    recolor: Recolor,
    visual_patch: VisualPatch,
    replace: struct { kind: ReplacementKind, rows: u16, cols: u16, cells: []const Cell },
    cursor: Cursor,
};

/// Bounds every allocation before one parser byte mutates semantic state.
pub const Budget = struct {
    operations: usize,
    cells: usize = 0,
    auxiliary_bytes: usize = 0,
};

/// Borrows one completed transaction until its terminal owner consumes it.
pub const Transaction = struct {
    operations: []const Operation,
};

/// Reports retained ownership, invalid bounds, or pre-mutation allocation failure.
pub const PrepareError = error{ TransactionPending, InvalidBudget, OutOfMemory };

/// Builds only within storage admitted before semantic mutation.
pub const Builder = struct {
    pending: *Pending,

    /// Reserves final resolved cells without allocating.
    pub fn cells(self: *Builder, count: usize) []Cell {
        std.debug.assert(count <= self.pending.cell_storage.len - self.pending.cell_count);
        const start = self.pending.cell_count;
        self.pending.cell_count += count;
        return self.pending.cell_storage[start..self.pending.cell_count];
    }

    /// Reserves exact mask or lookup bytes without allocating.
    pub fn bytes(self: *Builder, count: usize) []u8 {
        std.debug.assert(count <= self.pending.byte_storage.len - self.pending.byte_count);
        const start = self.pending.byte_count;
        self.pending.byte_count += count;
        return self.pending.byte_storage[start..self.pending.byte_count];
    }

    /// Appends one operation after all of its borrowed payload is initialized.
    pub fn append(self: *Builder, operation: Operation) void {
        std.debug.assert(self.pending.operation_count < self.pending.operation_storage.len);
        self.pending.operation_storage[self.pending.operation_count] = operation;
        self.pending.operation_count += 1;
    }

    /// Reports the admitted operation capacity for owner-level proofs.
    pub fn operationCapacity(self: *const Builder) usize {
        return self.pending.operation_storage.len;
    }
};

/// Retains at most one complete transaction until its future queue transfer.
pub const Pending = struct {
    inline_operations: [inline_operation_capacity]Operation = undefined,
    inline_cells: [inline_cell_capacity]Cell = undefined,
    operation_storage: []Operation = &.{},
    cell_storage: []Cell = &.{},
    byte_storage: []u8 = &.{},
    owned_operations: ?[]Operation = null,
    owned_payload: ?[]u8 = null,
    allocator: ?std.mem.Allocator = null,
    operation_count: usize = 0,
    cell_count: usize = 0,
    byte_count: usize = 0,
    prepared: bool = false,
    active: bool = false,

    /// Allocates every non-inline byte before semantic mutation begins.
    pub fn prepare(
        self: *Pending,
        allocator: std.mem.Allocator,
        budget: Budget,
    ) PrepareError!Builder {
        if (self.prepared or self.active) return error.TransactionPending;
        if (budget.operations == 0 or budget.cells > maximum_cells)
            return error.InvalidBudget;
        const cell_bytes = std.math.mul(usize, budget.cells, @sizeOf(Cell)) catch
            return error.InvalidBudget;
        const dynamic_cells = budget.cells > inline_cell_capacity;
        const payload_bytes = std.math.add(
            usize,
            if (dynamic_cells) cell_bytes else 0,
            budget.auxiliary_bytes,
        ) catch return error.InvalidBudget;

        if (budget.operations > inline_operation_capacity) {
            self.owned_operations = allocator.alloc(Operation, budget.operations) catch
                return error.OutOfMemory;
        }
        errdefer if (self.owned_operations) |operations| {
            allocator.free(operations);
            self.owned_operations = null;
        };
        if (payload_bytes != 0) {
            self.owned_payload = allocator.alloc(u8, payload_bytes) catch
                return error.OutOfMemory;
        }
        self.allocator = allocator;
        self.operation_storage = self.owned_operations orelse self.inline_operations[0..budget.operations];
        if (dynamic_cells) {
            self.cell_storage = @ptrCast(self.owned_payload.?[0..cell_bytes]);
            self.byte_storage = self.owned_payload.?[cell_bytes..];
        } else {
            self.cell_storage = self.inline_cells[0..budget.cells];
            self.byte_storage = if (self.owned_payload) |payload| payload else &.{};
        }
        self.operation_count = 0;
        self.cell_count = 0;
        self.byte_count = 0;
        self.prepared = true;
        return .{ .pending = self };
    }

    /// Publishes all completed operations atomically, or releases an empty plan.
    pub fn commit(self: *Pending) void {
        std.debug.assert(self.prepared and !self.active);
        if (self.operation_count == 0) {
            self.releaseStorage();
            return;
        }
        self.prepared = false;
        self.active = true;
    }

    /// Borrows the complete transaction without changing ownership.
    pub fn view(self: *const Pending) ?Transaction {
        if (!self.active) return null;
        return .{ .operations = self.operation_storage[0..self.operation_count] };
    }

    /// Releases one completed transaction after its next owner copied it.
    pub fn consume(self: *Pending) void {
        std.debug.assert(self.active);
        self.releaseStorage();
    }

    /// Cancels only a prepared or unpublished transaction.
    pub fn discard(self: *Pending) void {
        if (!self.prepared and !self.active) return;
        self.releaseStorage();
    }

    /// Releases retained dynamic payload during terminal teardown.
    pub fn deinit(self: *Pending) void {
        self.discard();
    }

    fn releaseStorage(self: *Pending) void {
        const allocator = self.allocator;
        if (self.owned_payload) |payload| allocator.?.free(payload);
        if (self.owned_operations) |operations| allocator.?.free(operations);
        self.operation_storage = &.{};
        self.cell_storage = &.{};
        self.byte_storage = &.{};
        self.owned_operations = null;
        self.owned_payload = null;
        self.allocator = null;
        self.operation_count = 0;
        self.cell_count = 0;
        self.byte_count = 0;
        self.prepared = false;
        self.active = false;
    }
};

comptime {
    std.debug.assert(@sizeOf(Rgb) == 3);
    std.debug.assert(@sizeOf(Cell) == 11);
    std.debug.assert(@alignOf(Cell) == 1);
    std.debug.assert(@sizeOf(Cursor) == 12);
}

test "journal visual layouts and recolor bound remain exact" {
    try std.testing.expectEqual(@as(usize, 11), @sizeOf(Cell));
    try std.testing.expectEqual(@as(usize, 12), @sizeOf(Cursor));
    try std.testing.expectEqual(@as(usize, 196_608), recolor_classification_bytes);
    try std.testing.expectEqual(@as(usize, 768), recolor_rgb_bytes);
}

test "replacement owns exact active payload and frees transactionally" {
    const cell: Cell = .{
        .codepoint = 'x',
        .foreground = .{ .r = 1, .g = 2, .b = 3 },
        .background = .{ .r = 4, .g = 5, .b = 6 },
        .underline_color = .{ .r = 7, .g = 8, .b = 9 },
    };
    const cells = [_]Cell{ cell, cell, cell, cell, cell, cell };
    var pending: Pending = .{};
    defer pending.deinit();
    var builder = try pending.prepare(std.testing.allocator, .{ .operations = 2, .cells = 6 });
    const copied = builder.cells(6);
    @memcpy(copied, &cells);
    builder.append(.{ .replace = .{
        .kind = .alternate,
        .rows = 2,
        .cols = 3,
        .cells = copied,
    } });
    builder.append(.{ .cursor = .{} });
    pending.commit();
    const transaction = pending.view().?;
    try std.testing.expectEqual(@as(usize, 2), transaction.operations.len);
    try std.testing.expectEqual(@as(u8, 'x'), transaction.operations[0].replace.cells[5].codepoint);
}

test "one pending transaction blocks before later ownership" {
    var pending: Pending = .{};
    var builder = try pending.prepare(std.testing.allocator, .{ .operations = 1 });
    builder.append(.{ .cursor = .{} });
    pending.commit();
    try std.testing.expectError(
        error.TransactionPending,
        pending.prepare(std.testing.allocator, .{ .operations = 1 }),
    );
    try std.testing.expectEqual(@as(usize, 1), pending.view().?.operations.len);
    pending.consume();
    var retry = try pending.prepare(std.testing.allocator, .{ .operations = 1 });
    std.mem.doNotOptimizeAway(&retry);
    pending.discard();
}
