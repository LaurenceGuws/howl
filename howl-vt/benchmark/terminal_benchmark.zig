const std = @import("std");
const terminal_mod = @import("../src/terminal.zig");
const pty_feed_record = @import("pty_feed_record.zig");
const stream_harness = @import("../test/support/stream_harness.zig");

const RunCount = u32;

const WorkloadResult = struct {
    name: []const u8,
    bytes_per_run: u64,
    runs: RunCount,
    median_ns: u64,
    p95_ns: u64,
    median_alloc_count: u64,
    median_alloc_bytes: u64,
    median_peak_live_bytes: u64,

    fn throughputMibS(self: WorkloadResult) f64 {
        const median_seconds = @as(f64, @floatFromInt(self.median_ns)) / 1_000_000_000.0;
        if (median_seconds <= 0) return 0;
        return (@as(f64, @floatFromInt(self.bytes_per_run)) / median_seconds) / (1024.0 * 1024.0);
    }
};

const OutputFormat = enum { ndjson, text };

const Options = struct {
    runs: RunCount = 10,
    format: OutputFormat = .ndjson,
    replay_paths: std.ArrayListUnmanaged([]const u8) = .empty,

    fn deinit(self: *Options, allocator: std.mem.Allocator) void {
        self.replay_paths.deinit(allocator);
        self.* = undefined;
    }
};

const ReplayFixture = struct {
    allocator: std.mem.Allocator,
    workload_name: []u8,
    record: pty_feed_record.Record,

    fn deinit(self: *ReplayFixture) void {
        self.record.deinit();
        self.allocator.free(self.workload_name);
        self.* = undefined;
    }
};

const RunObservation = struct {
    ns: u64,
    alloc_count: u64,
    alloc_bytes: u64,
    peak_live_bytes: u64,
};

const StreamHarness = stream_harness.Harness;

const CountingAllocator = struct {
    child: std.mem.Allocator,
    alloc_count: u64 = 0,
    alloc_bytes: u64 = 0,
    live_bytes: u64 = 0,
    peak_live_bytes: u64 = 0,
    window_alloc_count: u64 = 0,
    window_alloc_bytes: u64 = 0,
    window_peak_live_bytes: u64 = 0,
    window_live_baseline: u64 = 0,

    const vtable = std.mem.Allocator.VTable{
        .alloc = alloc,
        .resize = resize,
        .remap = remap,
        .free = free,
    };

    fn init(child: std.mem.Allocator) CountingAllocator {
        return .{ .child = child };
    }

    fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &vtable };
    }

    fn resetWindow(self: *CountingAllocator) void {
        self.window_alloc_count = 0;
        self.window_alloc_bytes = 0;
        self.window_peak_live_bytes = 0;
        self.window_live_baseline = self.live_bytes;
    }

    fn updateWindowPeak(self: *CountingAllocator) void {
        if (self.live_bytes >= self.window_live_baseline) {
            const delta = self.live_bytes - self.window_live_baseline;
            if (delta > self.window_peak_live_bytes) self.window_peak_live_bytes = delta;
        }
    }

    fn accountAlloc(self: *CountingAllocator, len: usize) void {
        self.alloc_count += 1;
        self.alloc_bytes += len;
        self.live_bytes += len;
        if (self.live_bytes > self.peak_live_bytes) self.peak_live_bytes = self.live_bytes;
        self.window_alloc_count += 1;
        self.window_alloc_bytes += len;
        self.updateWindowPeak();
    }

    fn accountResize(self: *CountingAllocator, old_len: usize, new_len: usize) void {
        if (new_len > old_len) {
            const delta = new_len - old_len;
            self.alloc_bytes += delta;
            self.window_alloc_bytes += delta;
            self.live_bytes += delta;
        } else {
            self.live_bytes -|= old_len - new_len;
        }
        self.updateWindowPeak();
    }

    // std.mem.Allocator owns architecture-sized lengths and return addresses at this callback seam.
    // Translate them immediately into fixed-width benchmark counters below.
    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.accountAlloc(len);
        return ptr;
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (!self.child.rawResize(memory, alignment, new_len, ret_addr)) return false;
        self.accountResize(memory.len, new_len);
        return true;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const ptr = self.child.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        self.accountResize(memory.len, new_len);
        return ptr;
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret_addr);
        self.live_bytes -|= memory.len;
        self.updateWindowPeak();
    }
};

fn lessThan(comptime T: type) fn (void, T, T) bool {
    return struct {
        fn compare(_: void, lhs: T, rhs: T) bool {
            return lhs < rhs;
        }
    }.compare;
}

fn median(comptime T: type, scratch: []T) T {
    std.sort.heap(T, scratch, {}, lessThan(T));
    return scratch[scratch.len / 2];
}

fn p95U64(scratch: []u64) u64 {
    std.sort.heap(u64, scratch, {}, lessThan(u64));
    const n = scratch.len;
    const idx = ((95 * n) + 99) / 100 - 1;
    return scratch[@min(idx, n - 1)];
}

fn nowNs(io: std.Io) u64 {
    return @intCast(std.Io.Clock.awake.now(io).toNanoseconds());
}

fn count32(items: anytype) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

fn count64(items: anytype) u64 {
    return count32(items);
}

fn buildAsciiFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 700_000);
    defer out.deinit(allocator);
    const line = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var i: u32 = 0;
    while (i < 10_000) : (i += 1) {
        try out.appendSlice(allocator, line);
        try out.appendSlice(allocator, "\r\n");
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn buildCsiFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 120_000);
    defer out.deinit(allocator);
    const block = "\x1b[H\x1b[2J\x1b[31mHELLO\x1b[0m\x1b[5C\x1b[2K\x1b[1;1H";
    var i: u32 = 0;
    while (i < 2_000) : (i += 1) {
        try out.appendSlice(allocator, block);
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn buildUnicodeFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 500_000);
    defer out.deinit(allocator);
    const line = "ASCII Привет 你好 Καλημέρα مرحبا 😀 λ─│┌┐└┘\r\n";
    var i: u32 = 0;
    while (i < 10_000) : (i += 1) {
        try out.appendSlice(allocator, line);
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn buildScrollFixture(allocator: std.mem.Allocator) ![]u8 {
    var out = try std.ArrayList(u8).initCapacity(allocator, 80_000);
    defer out.deinit(allocator);
    var i: u32 = 0;
    while (i < 20_000) : (i += 1) {
        try out.appendSlice(allocator, "X\r\n");
    }
    const owned = try allocator.alloc(u8, out.items.len);
    @memcpy(owned, out.items);
    return owned;
}

fn summarizeObservations(base_allocator: std.mem.Allocator, name: []const u8, bytes_per_run: u64, observations: []const RunObservation) !WorkloadResult {
    const runs = count32(observations);
    const ns_values = try base_allocator.alloc(u64, @intCast(runs));
    defer base_allocator.free(ns_values);
    const alloc_count_values = try base_allocator.alloc(u64, @intCast(runs));
    defer base_allocator.free(alloc_count_values);
    const alloc_bytes_values = try base_allocator.alloc(u64, @intCast(runs));
    defer base_allocator.free(alloc_bytes_values);
    const peak_live_values = try base_allocator.alloc(u64, @intCast(runs));
    defer base_allocator.free(peak_live_values);

    for (observations, 0..) |obs, idx| {
        ns_values[idx] = obs.ns;
        alloc_count_values[idx] = obs.alloc_count;
        alloc_bytes_values[idx] = obs.alloc_bytes;
        peak_live_values[idx] = obs.peak_live_bytes;
    }

    return .{
        .name = name,
        .bytes_per_run = bytes_per_run,
        .runs = runs,
        .median_ns = median(u64, ns_values),
        .p95_ns = p95U64(ns_values),
        .median_alloc_count = median(u64, alloc_count_values),
        .median_alloc_bytes = median(u64, alloc_bytes_values),
        .median_peak_live_bytes = median(u64, peak_live_values),
    };
}

fn runStreamWorkload(io: std.Io, base_allocator: std.mem.Allocator, name: []const u8, fixture: []const u8, rows: u16, cols: u16, history_capacity: u16, runs: RunCount) !WorkloadResult {
    const observations = try base_allocator.alloc(RunObservation, @intCast(runs));
    defer base_allocator.free(observations);
    var i: RunCount = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var terminal = try terminal_mod.Terminal.initWithHistory(
            counting.allocator(),
            rows,
            cols,
            history_capacity,
        );
        defer terminal.deinit();
        var stream = try StreamHarness.init(&terminal);
        counting.resetWindow();
        const start = nowNs(io);
        try stream.nextSlice(fixture);
        const end = nowNs(io);
        observations[@intCast(i)] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
        };
    }
    return try summarizeObservations(base_allocator, name, count64(fixture), observations);
}

fn runMixedInteractiveWorkload(io: std.Io, base_allocator: std.mem.Allocator, runs: RunCount) !WorkloadResult {
    const bursts_per_run: RunCount = 5_000;
    const burst = "abc\x1b[D\x1b[C\r";
    const observations = try base_allocator.alloc(RunObservation, @intCast(runs));
    defer base_allocator.free(observations);

    var i: RunCount = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var terminal = try terminal_mod.Terminal.initWithHistory(
            counting.allocator(),
            40,
            120,
            1_000,
        );
        defer terminal.deinit();
        var stream = try StreamHarness.init(&terminal);
        counting.resetWindow();
        const start = nowNs(io);
        var j: RunCount = 0;
        while (j < bursts_per_run) : (j += 1) {
            try stream.nextSlice(burst);
        }
        const end = nowNs(io);
        observations[@intCast(i)] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
        };
    }
    return try summarizeObservations(base_allocator, "mixed_interactive", @as(u64, bursts_per_run) * count64(burst), observations);
}

fn runSnapshotWorkload(io: std.Io, base_allocator: std.mem.Allocator, fixture: []const u8, runs: RunCount) !WorkloadResult {
    const snapshot_calls_per_run: RunCount = 200;
    const observations = try base_allocator.alloc(RunObservation, @intCast(runs));
    defer base_allocator.free(observations);

    var i: RunCount = 0;
    while (i < runs) : (i += 1) {
        var counting = CountingAllocator.init(base_allocator);
        var terminal = try terminal_mod.Terminal.initWithHistory(
            counting.allocator(),
            40,
            120,
            1_000,
        );
        defer terminal.deinit();
        var stream = try StreamHarness.init(&terminal);
        try stream.nextSlice(fixture);
        counting.resetWindow();
        const start = nowNs(io);
        var j: RunCount = 0;
        while (j < snapshot_calls_per_run) : (j += 1) {
            var snap = try @import("../test/support/screen_capture.zig").Capture.captureFromScreen(
                terminal.allocator,
                terminal.screen_state.activeConst(),
                terminal.screen_state.activeSelectionConst().state(),
            );
            snap.deinit();
        }
        const end = nowNs(io);
        observations[@intCast(i)] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
        };
    }
    return try summarizeObservations(base_allocator, "snapshot_opt_in", snapshot_calls_per_run, observations);
}

fn runReplayRecordWorkload(
    io: std.Io,
    base_allocator: std.mem.Allocator,
    name: []const u8,
    record: *const pty_feed_record.Record,
    rows: u16,
    cols: u16,
    history_capacity: u16,
    runs: u32,
) !WorkloadResult {
    const observations = try base_allocator.alloc(RunObservation, @intCast(runs));
    defer base_allocator.free(observations);

    for (observations) |*obs| {
        var counting = CountingAllocator.init(base_allocator);
        var terminal = try terminal_mod.Terminal.initWithHistory(
            counting.allocator(),
            rows,
            cols,
            history_capacity,
        );
        defer terminal.deinit();
        var stream = try StreamHarness.init(&terminal);

        counting.resetWindow();
        const start = nowNs(io);
        for (record.chunks.items) |chunk| {
            try stream.nextSlice(chunk);
        }
        const end = nowNs(io);
        obs.* = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
        };
    }
    return try summarizeObservations(base_allocator, name, @intCast(pty_feed_record.byteLen(record)), observations);
}

fn loadReplayFixtures(io: std.Io, allocator: std.mem.Allocator, replay_paths: []const []const u8) ![]ReplayFixture {
    var fixtures: std.ArrayList(ReplayFixture) = .empty;
    errdefer {
        for (fixtures.items) |*fixture| fixture.deinit();
        fixtures.deinit(allocator);
    }

    for (replay_paths) |replay_path| {
        if (!std.mem.endsWith(u8, replay_path, ".hex")) return error.InvalidReplayPath;

        var record = try pty_feed_record.load(io, allocator, replay_path);
        errdefer record.deinit();
        if (record.chunks.items.len == 0) {
            record.deinit();
            continue;
        }

        const file_name = std.fs.path.basename(replay_path);
        const workload_name = try replayWorkloadName(allocator, file_name);
        errdefer allocator.free(workload_name);
        try fixtures.append(allocator, .{
            .allocator = allocator,
            .workload_name = workload_name,
            .record = record,
        });
    }

    std.sort.heap(ReplayFixture, fixtures.items, {}, lessThanReplayFixture);
    return try fixtures.toOwnedSlice(allocator);
}

fn replayWorkloadName(allocator: std.mem.Allocator, file_name: []const u8) ![]u8 {
    const stem = std.fs.path.stem(file_name);
    const name = try allocator.alloc(u8, "replay_".len + stem.len);
    @memcpy(name[0.."replay_".len], "replay_");
    for (stem, 0..) |byte, idx| {
        name["replay_".len + idx] = switch (byte) {
            'a'...'z', 'A'...'Z', '0'...'9' => byte,
            else => '_',
        };
    }
    return name;
}

fn lessThanReplayFixture(_: void, lhs: ReplayFixture, rhs: ReplayFixture) bool {
    return std.mem.lessThan(u8, lhs.workload_name, rhs.workload_name);
}

fn deinitReplayFixtures(fixtures: []ReplayFixture) void {
    for (fixtures) |*fixture| fixture.deinit();
}

test "replay workload name derives from fixture basename" {
    const gpa = std.testing.allocator;
    const name = try replayWorkloadName(gpa, "capture-1.hex");
    defer gpa.free(name);
    try std.testing.expectEqualStrings("replay_capture_1", name);
}

test "parse options keeps explicit replay paths" {
    const gpa = std.testing.allocator;
    const args: []const []const u8 = &.{
        "vt_core_benchmark",
        "--runs",
        "3",
        "--text",
        "--replay",
        "fixtures/one.hex",
        "--replay",
        "fixtures/two.hex",
    };

    var options = try parseOptions(gpa, @ptrCast(args));
    defer options.deinit(gpa);

    try std.testing.expectEqual(@as(RunCount, 3), options.runs);
    try std.testing.expectEqual(OutputFormat.text, options.format);
    try std.testing.expectEqual(@as(usize, 2), options.replay_paths.items.len);
    try std.testing.expectEqualStrings("fixtures/one.hex", options.replay_paths.items[0]);
    try std.testing.expectEqualStrings("fixtures/two.hex", options.replay_paths.items[1]);
}

test "load replay fixtures rejects non-hex path" {
    try std.testing.expectError(
        error.InvalidReplayPath,
        loadReplayFixtures(std.testing.ios, std.testing.allocator, &.{"fixtures/plain.txt"}),
    );
}

fn printTextResult(result: WorkloadResult) void {
    const median_ms = @as(f64, @floatFromInt(result.median_ns)) / 1_000_000.0;
    const p95_ms = @as(f64, @floatFromInt(result.p95_ns)) / 1_000_000.0;

    std.debug.print("workload={s}\n", .{result.name});
    std.debug.print("runs={d}\n", .{result.runs});
    std.debug.print("bytes_per_run={d}\n", .{result.bytes_per_run});
    std.debug.print("median_ms={d:.3}\n", .{median_ms});
    std.debug.print("p95_ms={d:.3}\n", .{p95_ms});
    std.debug.print("throughput_mib_s={d:.2}\n", .{result.throughputMibS()});
    std.debug.print("median_alloc_count={d}\n", .{result.median_alloc_count});
    std.debug.print("median_alloc_bytes={d}\n", .{result.median_alloc_bytes});
    std.debug.print("median_peak_live_bytes={d}\n", .{result.median_peak_live_bytes});
    std.debug.print("---\n", .{});
}

fn printNdjsonResult(result: WorkloadResult) void {
    std.debug.print(
        "{{\"type\":\"vt_core_benchmark\",\"schema\":4,\"workload\":\"{s}\",\"runs\":{d}," ++
            "\"bytes_per_run\":{d},\"median_ns\":{d},\"p95_ns\":{d},\"throughput_mib_s\":{d:.3}," ++
            "\"median_alloc_count\":{d},\"median_alloc_bytes\":{d},\"median_peak_live_bytes\":{d}}}\n",
        .{
            result.name,
            result.runs,
            result.bytes_per_run,
            result.median_ns,
            result.p95_ns,
            result.throughputMibS(),
            result.median_alloc_count,
            result.median_alloc_bytes,
            result.median_peak_live_bytes,
        },
    );
}

fn printResult(result: WorkloadResult, format: OutputFormat) void {
    switch (format) {
        .ndjson => printNdjsonResult(result),
        .text => printTextResult(result),
    }
}

fn usage() void {
    return;
}

fn parseOptions(allocator: std.mem.Allocator, args_vector: std.process.Args.Vector) !Options {
    var args = std.process.Args.Iterator.init(.{ .vector = args_vector });
    _ = args.next();
    var options = Options{};
    errdefer options.deinit(allocator);
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            usage();
            return error.HelpRequested;
        } else if (std.mem.eql(u8, arg, "--text")) {
            options.format = .text;
        } else if (std.mem.eql(u8, arg, "--runs")) {
            const value = args.next() orelse return error.InvalidArgs;
            options.runs = @max(try std.fmt.parseInt(RunCount, value, 10), 1);
        } else if (std.mem.eql(u8, arg, "--replay")) {
            const replay_path = args.next() orelse return error.InvalidArgs;
            try options.replay_paths.append(allocator, replay_path);
        } else {
            usage();
            return error.InvalidArgs;
        }
    }
    return options;
}

/// Benchmark entrypoint.
pub fn main(init: std.process.Init) !void {
    const allocator = std.heap.page_allocator;
    var options = parseOptions(allocator, init.minimal.args.vector) catch |err| switch (err) {
        error.HelpRequested => return,
        else => return err,
    };
    defer options.deinit(allocator);
    const runs = options.runs;

    const ascii_fixture = try buildAsciiFixture(allocator);
    defer allocator.free(ascii_fixture);
    const unicode_fixture = try buildUnicodeFixture(allocator);
    defer allocator.free(unicode_fixture);
    const csi_fixture = try buildCsiFixture(allocator);
    defer allocator.free(csi_fixture);
    const scroll_fixture = try buildScrollFixture(allocator);
    defer allocator.free(scroll_fixture);

    const ascii_result = try runStreamWorkload(
        init.io,
        allocator,
        "ascii_heavy",
        ascii_fixture,
        40,
        120,
        0,
        runs,
    );
    const csi_result = try runStreamWorkload(
        init.io,
        allocator,
        "csi_heavy",
        csi_fixture,
        40,
        120,
        0,
        runs,
    );
    const unicode_result = try runStreamWorkload(
        init.io,
        allocator,
        "unicode_heavy",
        unicode_fixture,
        40,
        120,
        0,
        runs,
    );
    const scroll_no_history = try runStreamWorkload(
        init.io,
        allocator,
        "scroll_heavy_history0",
        scroll_fixture,
        40,
        120,
        0,
        runs,
    );
    const scroll_with_history = try runStreamWorkload(
        init.io,
        allocator,
        "scroll_heavy_history1000",
        scroll_fixture,
        40,
        120,
        1_000,
        runs,
    );
    const scroll_with_default_history = try runStreamWorkload(
        init.io,
        allocator,
        "scroll_heavy_history4096",
        scroll_fixture,
        40,
        120,
        4_096,
        runs,
    );
    const mixed_result = try runMixedInteractiveWorkload(init.io, allocator, runs);
    const snapshot_result = try runSnapshotWorkload(init.io, allocator, scroll_fixture, runs);

    const replay_fixtures = try loadReplayFixtures(init.io, allocator, options.replay_paths.items);
    defer deinitReplayFixtures(replay_fixtures);

    if (options.format == .text) {
        std.debug.print("vt_core_benchmark_v2\n", .{});
        std.debug.print("rows=40 cols=120 runs={d}\n", .{runs});
        std.debug.print("---\n", .{});
    }

    printResult(ascii_result, options.format);
    printResult(unicode_result, options.format);
    printResult(csi_result, options.format);
    printResult(scroll_no_history, options.format);
    printResult(scroll_with_history, options.format);
    printResult(scroll_with_default_history, options.format);
    printResult(mixed_result, options.format);
    printResult(snapshot_result, options.format);
    for (replay_fixtures) |*fixture| {
        const result = try runReplayRecordWorkload(
            init.io,
            allocator,
            fixture.workload_name,
            &fixture.record,
            40,
            120,
            1_000,
            @intCast(runs),
        );
        printResult(result, options.format);
    }
}
