const std = @import("std");
const terminal_mod = @import("../src/terminal.zig");

// Shared VT simulation helper for scrollback churn. Workloads use deterministic
// seeded input space with explicit preservation claims.

const Terminal = terminal_mod.Terminal;

pub const RowsMin: u16 = 1;
pub const ColsMin: u16 = 1;
pub const RowsMax: u16 = 80;
pub const ColsMax: u16 = 220;

const BurstCount = u32;
const ScenarioOpCount = u32;

const OpKind = enum {
    write_burst,
    resize,
    zoom_jitter,
};

pub const RunSummary = struct {
    structural_hash: u64,
    logical_hash: u64,
    history_count: u32,
    rows: u16,
    cols: u16,
};

pub const ChurnStep = union(enum) {
    resize: struct { rows: u16, cols: u16 },
    zoom_jitter: struct {
        start_rows: u16,
        start_cols: u16,
        end_rows: u16,
        end_cols: u16,
        steps: u8,
    },
};

pub const CoreStateSummary = struct {
    rows: u16,
    cols: u16,
    wrap_pending: bool,
    history_count: u32,
    history_capacity: u16,
};

pub const PreservationOptions = struct {
    initial_rows: u16 = 24,
    initial_cols: u16 = 80,
    history_capacity: u16 = 4096,
    warmup_bursts: BurstCount = 320,
    churn_ops: ScenarioOpCount = 400,
};

pub const InvariantError = error{
    RowBelowMinimum,
    ColBelowMinimum,
};

pub fn runScenario(allocator: std.mem.Allocator, seed: u64, op_count: ScenarioOpCount) !RunSummary {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var vt = try Terminal.initWithHistory(allocator, 24, 80, 4096);
    defer vt.deinit();

    var i: ScenarioOpCount = 0;
    while (i < op_count) : (i += 1) {
        const op = pickOp(rand);
        switch (op) {
            .write_burst => try applyWriteBurst(&vt, rand),
            .resize => try applyResize(&vt, rand),
            .zoom_jitter => try applyZoomJitter(&vt, rand),
        }
        try ensureCoreInvariants(&vt);
    }

    return .{
        .structural_hash = hashStructural(&vt),
        .logical_hash = hashLogicalContent(&vt),
        .history_count = vt.visibleHistoryCount(),
        .rows = vt.screen_state.activeConst().rows,
        .cols = vt.screen_state.activeConst().cols,
    };
}

pub fn runCanonicalPreservation(allocator: std.mem.Allocator, seed: u64, options: PreservationOptions) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    var vt = try Terminal.initWithHistory(
        allocator,
        options.initial_rows,
        options.initial_cols,
        options.history_capacity,
    );
    defer vt.deinit();

    var line_idx: BurstCount = 0;
    while (line_idx < options.warmup_bursts) : (line_idx += 1) {
        try applyWriteBurst(&vt, rand);
    }

    const before = canonicalLogicalHash(&vt);

    var churn_idx: ScenarioOpCount = 0;
    while (churn_idx < options.churn_ops) : (churn_idx += 1) {
        const pre_state = summarizeCoreState(&vt);
        const step = if (rand.boolean())
            try applyResizeStep(&vt, rand)
        else
            try applyZoomJitterStep(&vt, rand);
        const actual = canonicalLogicalHash(&vt);
        if (actual != before) {
            logBreakpoint(churn_idx, pre_state, step, before, actual, summarizeCoreState(&vt));
            return error.CanonicalContentMismatch;
        }

        try ensureCoreInvariants(&vt);
    }

    const restore_pre_state = summarizeCoreState(&vt);
    try vt.screen_state.resize(vt.allocator, options.initial_rows, options.initial_cols);
    vt.screen_state.activeSelection().clearIfInvalidatedByGrid(vt.screen_state.activeConst());
    const restore_step: ChurnStep = .{ .resize = .{
        .rows = options.initial_rows,
        .cols = options.initial_cols,
    } };
    try ensureCoreInvariants(&vt);

    const after = canonicalLogicalHash(&vt);
    if (after != before) {
        logBreakpoint(options.churn_ops, restore_pre_state, restore_step, before, after, summarizeCoreState(&vt));
        return error.CanonicalContentMismatch;
    }
}

pub fn parseSeed(bytes: []const u8) !u64 {
    if (bytes.len == 40) {
        const commit_hash = std.fmt.parseUnsigned(u160, bytes, 16) catch |err| switch (err) {
            error.Overflow => unreachable,
            error.InvalidCharacter => return error.InvalidSeed,
        };
        return @truncate(commit_hash);
    }

    return std.fmt.parseUnsigned(u64, bytes, 10) catch return error.InvalidSeed;
}

pub fn defaultPreservationOptions(events_max: ?ScenarioOpCount) PreservationOptions {
    var options: PreservationOptions = .{};
    options.churn_ops = events_max orelse options.churn_ops;
    return options;
}

fn pickOp(rand: std.Random) OpKind {
    const roll = rand.uintLessThan(u8, 100);
    if (roll < 45) return .write_burst;
    if (roll < 80) return .resize;
    return .zoom_jitter;
}

fn applyWriteBurst(vt: *Terminal, rand: std.Random) !void {
    var stream = vt.vtStream();
    const lines = rand.uintLessThan(u8, 8) + 1;
    var line_idx: u8 = 0;
    while (line_idx < lines) : (line_idx += 1) {
        var buf: [96]u8 = undefined;
        const len = rand.uintLessThan(u8, 90) + 1;
        var i: u8 = 0;
        while (i < len) : (i += 1) {
            const cp = "0123456789abcdefXYZ+-_=./[]{}()";
            buf[@intCast(i)] = cp[@intCast(rand.uintLessThan(u8, @intCast(cp.len)))];
        }
        try stream.nextSlice(buf[0..len]);
        try stream.next('\n');
    }
}

fn applyResize(vt: *Terminal, rand: std.Random) !void {
    const rows = RowsMin + rand.uintLessThan(u16, RowsMax - RowsMin + 1);
    const cols = ColsMin + rand.uintLessThan(u16, ColsMax - ColsMin + 1);
    try vt.screen_state.resize(vt.allocator, rows, cols);
    vt.screen_state.activeSelection().clearIfInvalidatedByGrid(vt.screen_state.activeConst());
}

fn applyResizeStep(vt: *Terminal, rand: std.Random) !ChurnStep {
    const rows = RowsMin + rand.uintLessThan(u16, RowsMax - RowsMin + 1);
    const cols = ColsMin + rand.uintLessThan(u16, ColsMax - ColsMin + 1);
    try vt.screen_state.resize(vt.allocator, rows, cols);
    vt.screen_state.activeSelection().clearIfInvalidatedByGrid(vt.screen_state.activeConst());
    return .{ .resize = .{ .rows = rows, .cols = cols } };
}

fn applyZoomJitter(vt: *Terminal, rand: std.Random) !void {
    const cur_rows = vt.screen_state.activeConst().rows;
    const cur_cols = vt.screen_state.activeConst().cols;
    const steps = rand.uintLessThan(u8, 5) + 2;
    var i: u8 = 0;
    while (i < steps) : (i += 1) {
        const delta_rows: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 7))) - 3;
        const delta_cols: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 19))) - 9;
        const next_rows = clampDimI16(cur_rows, delta_rows, RowsMin, RowsMax);
        const next_cols = clampDimI16(cur_cols, delta_cols, ColsMin, ColsMax);
        try vt.screen_state.resize(vt.allocator, next_rows, next_cols);
        vt.screen_state.activeSelection().clearIfInvalidatedByGrid(vt.screen_state.activeConst());
    }
    try vt.screen_state.resize(vt.allocator, cur_rows, cur_cols);
    vt.screen_state.activeSelection().clearIfInvalidatedByGrid(vt.screen_state.activeConst());
}

fn applyZoomJitterStep(vt: *Terminal, rand: std.Random) !ChurnStep {
    const cur_rows = vt.screen_state.activeConst().rows;
    const cur_cols = vt.screen_state.activeConst().cols;
    const steps = rand.uintLessThan(u8, 5) + 2;
    var end_rows = cur_rows;
    var end_cols = cur_cols;
    var i: u8 = 0;
    while (i < steps) : (i += 1) {
        const delta_rows: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 7))) - 3;
        const delta_cols: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 19))) - 9;
        end_rows = clampDimI16(cur_rows, delta_rows, RowsMin, RowsMax);
        end_cols = clampDimI16(cur_cols, delta_cols, ColsMin, ColsMax);
        try vt.screen_state.resize(vt.allocator, end_rows, end_cols);
        vt.screen_state.activeSelection().clearIfInvalidatedByGrid(vt.screen_state.activeConst());
    }
    try vt.screen_state.resize(vt.allocator, cur_rows, cur_cols);
    vt.screen_state.activeSelection().clearIfInvalidatedByGrid(vt.screen_state.activeConst());
    return .{ .zoom_jitter = .{
        .start_rows = cur_rows,
        .start_cols = cur_cols,
        .end_rows = end_rows,
        .end_cols = end_cols,
        .steps = steps,
    } };
}

fn clampDimI16(base: u16, delta: i16, min_v: u16, max_v: u16) u16 {
    const signed = @as(i32, @intCast(base)) + @as(i32, delta);
    const clamped = std.math.clamp(signed, @as(i32, @intCast(min_v)), @as(i32, @intCast(max_v)));
    return @intCast(clamped);
}

fn ensureCoreInvariants(vt: *const Terminal) InvariantError!void {
    const s = vt.screen_state.activeConst();
    if (s.rows < RowsMin) return error.RowBelowMinimum;
    if (s.cols < ColsMin) return error.ColBelowMinimum;
}

fn hashStructural(vt: *const Terminal) u64 {
    var h = std.hash.Wyhash.init(0);
    const s = vt.screen_state.activeConst();
    h.update(std.mem.asBytes(&s.rows));
    h.update(std.mem.asBytes(&s.cols));
    h.update(std.mem.asBytes(&s.wrap_pending));
    const history_count = vt.visibleHistoryCount();
    const history_capacity = s.historyCapacity();
    h.update(std.mem.asBytes(&history_count));
    h.update(std.mem.asBytes(&history_capacity));
    return h.final();
}

fn hashLogicalContent(vt: *const Terminal) u64 {
    var h = std.hash.Wyhash.init(0x9e3779b97f4a7c15);
    const s = vt.screen_state.activeConst();
    const history = vt.visibleHistoryCount();

    var hr: u32 = 0;
    while (hr < history) : (hr += 1) {
        var col: u16 = 0;
        while (col < s.cols) : (col += 1) {
            const cp = s.historyRowAt(hr, col);
            h.update(std.mem.asBytes(&cp));
        }
    }

    var row: u16 = 0;
    while (row < s.rows) : (row += 1) {
        var col: u16 = 0;
        while (col < s.cols) : (col += 1) {
            const cp = s.cellAt(row, col);
            h.update(std.mem.asBytes(&cp));
        }
    }

    return h.final();
}

fn canonicalLogicalHash(vt: *const Terminal) u64 {
    var h = std.hash.Wyhash.init(0xd1b54a32d192ed03);

    const s = vt.screen_state.activeConst();
    const row_break: u32 = 0;

    for (s.history_lines.items, 0..) |_, line_idx| {
        const slot = (s.history_lines_start + @as(u32, @intCast(line_idx))) % @as(u32, @intCast(s.history_lines.items.len));
        const line = s.history_lines.items[@intCast(slot)];
        h.update(std.mem.asBytes(&row_break));
        for (line.cells.items) |cell| {
            const codepoint: u32 = @intCast(cell.codepoint);
            h.update(std.mem.asBytes(&codepoint));
        }
    }

    var open_prefix_len: usize = 0;
    if (s.open_history_line) |open_line| {
        h.update(std.mem.asBytes(&row_break));
        for (open_line.cells.items) |cell| {
            const codepoint: u32 = @intCast(cell.codepoint);
            h.update(std.mem.asBytes(&codepoint));
        }
        open_prefix_len = open_line.cells.items.len;
    }

    var pending_visible = false;

    var row: u16 = 0;
    while (row < s.rows) : (row += 1) {
        const len = visibleContentLen(s, row, s.cols);
        var col: u16 = 0;
        if (!pending_visible and (row > 0 or open_prefix_len == 0)) {
            h.update(std.mem.asBytes(&row_break));
        }
        pending_visible = true;
        while (col < len) : (col += 1) {
            const codepoint: u32 = s.cellAt(row, col);
            h.update(std.mem.asBytes(&codepoint));
        }
        if (!s.rowWrapped(row)) {
            pending_visible = false;
        }
    }

    if (!pending_visible and s.history_lines.items.len == 0 and open_prefix_len == 0 and s.rows == 0) {
        h.update(std.mem.asBytes(&row_break));
    }
    return h.final();
}

fn visibleContentLen(s: anytype, row: u16, cols: u16) u16 {
    var col = cols;
    while (col > 0) {
        const idx = col - 1;
        if (s.cellAt(row, idx) != 0) return col;
        col -= 1;
    }
    if (s.rowWrapped(row) and cols > 0) return cols;
    return 0;
}

fn summarizeCoreState(vt: *const Terminal) CoreStateSummary {
    const s = vt.screen_state.activeConst();
    return .{
        .rows = s.rows,
        .cols = s.cols,
        .wrap_pending = s.wrap_pending,
        .history_count = vt.visibleHistoryCount(),
        .history_capacity = s.historyCapacity(),
    };
}

fn logBreakpoint(index: ScenarioOpCount, before: CoreStateSummary, step: ChurnStep, expected: u64, actual: u64, after: CoreStateSummary) void {
    std.debug.print(
        "scrollback simulation breakpoint at step {d}\nstate before: rows={d} cols={d} wrap_pending={} history={d}/{d}\n",
        .{
            index,
            before.rows,
            before.cols,
            before.wrap_pending,
            before.history_count,
            before.history_capacity,
        },
    );
    switch (step) {
        .resize => |v| std.debug.print("step: resize rows={d} cols={d}\n", .{ v.rows, v.cols }),
        .zoom_jitter => |v| std.debug.print(
            "step: zoom_jitter start={d}x{d} last_jitter={d}x{d} steps={d} restored_to_start\n",
            .{ v.start_rows, v.start_cols, v.end_rows, v.end_cols, v.steps },
        ),
    }
    std.debug.print("expected output hash: {d}\nactual output hash: {d}\n", .{ expected, actual });
    std.debug.print(
        "state after: rows={d} cols={d} wrap_pending={} history={d}/{d}\n",
        .{
            after.rows,
            after.cols,
            after.wrap_pending,
            after.history_count,
            after.history_capacity,
        },
    );
}
