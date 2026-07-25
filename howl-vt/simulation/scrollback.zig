const std = @import("std");
const terminal_mod = @import("../src/howl_vt.zig");

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
    history_count: u32,
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
        .history_count = vt.semanticView(0).history_count,
        .rows = vt.semanticView(0).rows,
        .cols = vt.semanticView(0).cols,
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
    try vt.resize(options.initial_rows, options.initial_cols);
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
        try feedChecked(vt, buf[0..len]);
        try feedChecked(vt, "\n");
    }
}

fn feedChecked(vt: *Terminal, bytes: []const u8) !void {
    const summary = try vt.feed(bytes);
    std.debug.assert(!summary.history_lost or summary.state_changed);
}

fn applyResize(vt: *Terminal, rand: std.Random) !void {
    const rows = RowsMin + rand.uintLessThan(u16, RowsMax - RowsMin + 1);
    const cols = ColsMin + rand.uintLessThan(u16, ColsMax - ColsMin + 1);
    try vt.resize(rows, cols);
}

fn applyResizeStep(vt: *Terminal, rand: std.Random) !ChurnStep {
    const rows = RowsMin + rand.uintLessThan(u16, RowsMax - RowsMin + 1);
    const cols = ColsMin + rand.uintLessThan(u16, ColsMax - ColsMin + 1);
    try vt.resize(rows, cols);
    return .{ .resize = .{ .rows = rows, .cols = cols } };
}

fn applyZoomJitter(vt: *Terminal, rand: std.Random) !void {
    const view = vt.semanticView(0);
    const cur_rows = view.rows;
    const cur_cols = view.cols;
    const steps = rand.uintLessThan(u8, 5) + 2;
    var i: u8 = 0;
    while (i < steps) : (i += 1) {
        const delta_rows: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 7))) - 3;
        const delta_cols: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 19))) - 9;
        const next_rows = clampDimI16(cur_rows, delta_rows, RowsMin, RowsMax);
        const next_cols = clampDimI16(cur_cols, delta_cols, ColsMin, ColsMax);
        try vt.resize(next_rows, next_cols);
    }
    try vt.resize(cur_rows, cur_cols);
}

fn applyZoomJitterStep(vt: *Terminal, rand: std.Random) !ChurnStep {
    const view = vt.semanticView(0);
    const cur_rows = view.rows;
    const cur_cols = view.cols;
    const steps = rand.uintLessThan(u8, 5) + 2;
    var end_rows = cur_rows;
    var end_cols = cur_cols;
    var i: u8 = 0;
    while (i < steps) : (i += 1) {
        const delta_rows: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 7))) - 3;
        const delta_cols: i16 = @as(i16, @intCast(rand.uintLessThan(u8, 19))) - 9;
        end_rows = clampDimI16(cur_rows, delta_rows, RowsMin, RowsMax);
        end_cols = clampDimI16(cur_cols, delta_cols, ColsMin, ColsMax);
        try vt.resize(end_rows, end_cols);
    }
    try vt.resize(cur_rows, cur_cols);
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
    const view = vt.semanticView(0);
    if (view.rows < RowsMin) return error.RowBelowMinimum;
    if (view.cols < ColsMin) return error.ColBelowMinimum;
}

fn hashStructural(vt: *const Terminal) u64 {
    var h = std.hash.Wyhash.init(0);
    const view = vt.semanticView(0);
    h.update(std.mem.asBytes(&view.rows));
    h.update(std.mem.asBytes(&view.cols));
    const history_count = view.history_count;
    h.update(std.mem.asBytes(&history_count));
    return h.final();
}

fn hashLogicalContent(vt: *const Terminal) u64 {
    var h = std.hash.Wyhash.init(0x9e3779b97f4a7c15);
    const view = vt.semanticView(0);
    const history = view.history_count;

    var hr: u32 = 0;
    while (hr < history) : (hr += 1) {
        const history_view = vt.semanticView(hr + 1);
        var col: u16 = 0;
        while (col < history_view.cols) : (col += 1) {
            const cp = history_view.cellAt(0, col);
            h.update(std.mem.asBytes(&cp));
        }
    }

    var row: u16 = 0;
    while (row < view.rows) : (row += 1) {
        var col: u16 = 0;
        const len = visibleContentLen(&view, row, view.cols);
        while (col < len) : (col += 1) {
            const cp = view.cellAt(row, col);
            h.update(std.mem.asBytes(&cp));
        }
    }

    return h.final();
}

fn visibleContentLen(s: *const Terminal.SemanticView, row: u16, cols: u16) u16 {
    var col = cols;
    while (col > 0) {
        const idx = col - 1;
        if (s.cellAt(row, idx) != 0) return col;
        col -= 1;
    }
    if (s.rowWrapped(row) and cols > 0) return cols;
    return 0;
}

fn canonicalLogicalHash(vt: *const Terminal) u64 {
    var h = std.hash.Wyhash.init(0xd1b54a32d192ed03);
    var output = vt.copyLogicalOutput(std.heap.page_allocator, 0, std.math.maxInt(u16), 1024 * 1024) catch return 0;
    switch (output) {
        .output => |*value| {
            defer value.deinit();
            h.update(value.text);
            h.update(value.open_line);
            h.update(std.mem.asBytes(&value.open_line_omitted));
            for (value.losses) |loss| {
                h.update(std.mem.asBytes(&loss.id));
                h.update(std.mem.asBytes(&loss.byte_count));
                h.update(std.mem.asBytes(&loss.reason));
            }
        },
        else => return 0,
    }
    return h.final();
}

fn summarizeCoreState(vt: *const Terminal) CoreStateSummary {
    const view = vt.semanticView(0);
    return .{
        .rows = view.rows,
        .cols = view.cols,
        .history_count = view.history_count,
    };
}

fn logBreakpoint(index: ScenarioOpCount, before: CoreStateSummary, step: ChurnStep, expected: u64, actual: u64, after: CoreStateSummary) void {
    std.debug.print(
        "scrollback simulation breakpoint at step {d}\nstate before: rows={d} cols={d} history={d}\n",
        .{
            index,
            before.rows,
            before.cols,
            before.history_count,
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
        "state after: rows={d} cols={d} history={d}\n",
        .{
            after.rows,
            after.cols,
            after.history_count,
        },
    );
}
