const std = @import("std");
const terminal_mod = @import("howl_vt");

fn feed(terminal: *terminal_mod.Terminal, bytes: []const u8) terminal_mod.Terminal.FeedError!void {
    const summary = try terminal.feed(bytes);
    std.debug.assert(!summary.historyLost() or summary.stateChanged());
}

const RunCount = u32;

const WorkloadResult = struct {
    name: []const u8,
    bytes_per_run: u64,
    runs: RunCount,
    median_ns: u64,
    max_ns: u64,
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
};

const RunObservation = struct {
    ns: u64,
    alloc_count: u64,
    alloc_bytes: u64,
    peak_live_bytes: u64,
};

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

fn maximumU64(values: []const u64) u64 {
    var result: u64 = 0;
    for (values) |value| result = @max(result, value);
    return result;
}

fn nowNs(io: std.Io) u64 {
    return @intCast(std.Io.Clock.awake.now(io).toNanoseconds());
}

fn observationCount32(items: []const RunObservation) u32 {
    std.debug.assert(items.len <= std.math.maxInt(u32));
    return @intCast(items.len);
}

fn byteCount64(bytes: []const u8) u64 {
    std.debug.assert(bytes.len <= std.math.maxInt(u64));
    return @intCast(bytes.len);
}

fn buildRepeatedFixture(
    allocator: std.mem.Allocator,
    line: []const u8,
    suffix: []const u8,
    count: u32,
) ![]u8 {
    const per_line = std.math.add(usize, line.len, suffix.len) catch
        return error.OutOfMemory;
    const capacity = std.math.mul(usize, per_line, count) catch
        return error.OutOfMemory;
    var out = try std.ArrayList(u8).initCapacity(allocator, capacity);
    defer out.deinit(allocator);
    var i: u32 = 0;
    while (i < count) : (i += 1) {
        try out.appendSlice(allocator, line);
        try out.appendSlice(allocator, suffix);
    }
    return try out.toOwnedSlice(allocator);
}

fn buildAsciiOverwriteFixture(allocator: std.mem.Allocator) ![]u8 {
    return buildRepeatedFixture(
        allocator,
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
        "\r",
        10_000,
    );
}

fn buildAsciiScrollFixture(allocator: std.mem.Allocator) ![]u8 {
    return buildRepeatedFixture(
        allocator,
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/",
        "\r\n",
        10_000,
    );
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

fn buildUnicodeOverwriteFixture(allocator: std.mem.Allocator) ![]u8 {
    return buildRepeatedFixture(
        allocator,
        "ASCII Привет 你好 Καλημέρα مرحبا 😀 λ─│┌┐└┘",
        "\r",
        10_000,
    );
}

fn buildLineFeedScrollFixture(allocator: std.mem.Allocator) ![]u8 {
    return buildRepeatedFixture(allocator, "X", "\r\n", 20_000);
}

fn summarizeObservations(base_allocator: std.mem.Allocator, name: []const u8, bytes_per_run: u64, observations: []const RunObservation) !WorkloadResult {
    const runs = observationCount32(observations);
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
        .max_ns = maximumU64(ns_values),
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
        counting.resetWindow();
        const start = nowNs(io);
        try feed(&terminal, fixture);
        const end = nowNs(io);
        if (history_capacity == 0 and counting.window_alloc_count != 0)
            return error.SteadyStateAllocation;
        observations[@intCast(i)] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
        };
    }
    return try summarizeObservations(base_allocator, name, byteCount64(fixture), observations);
}

fn runWarmStreamWorkload(
    io: std.Io,
    base_allocator: std.mem.Allocator,
    name: []const u8,
    warmup: []const u8,
    fixture: []const u8,
    rows: u16,
    cols: u16,
    history_capacity: u16,
    runs: RunCount,
) !WorkloadResult {
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

        try feed(&terminal, warmup);
        counting.resetWindow();
        const start = nowNs(io);
        try feed(&terminal, fixture);
        const end = nowNs(io);
        if (counting.window_alloc_count != 0)
            return error.SteadyStateAllocation;
        observations[@intCast(i)] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
        };
    }
    return try summarizeObservations(
        base_allocator,
        name,
        byteCount64(fixture),
        observations,
    );
}

fn feedServiceChunks(
    terminal: *terminal_mod.Terminal,
    bytes: []const u8,
    chunk_bytes: usize,
) terminal_mod.Terminal.FeedError!void {
    var offset: usize = 0;
    var timestamp_ns: u64 = 1;
    while (offset < bytes.len) {
        const end = @min(offset + chunk_bytes, bytes.len);
        while (offset < end) {
            const progress = try terminal.feedAtServiceBoundary(
                bytes[offset..end],
                timestamp_ns,
            );
            std.debug.assert(progress.consumed > 0);
            offset += progress.consumed;
            timestamp_ns += 1;
        }
    }
}

fn runWarmServiceWorkload(
    io: std.Io,
    base_allocator: std.mem.Allocator,
    name: []const u8,
    warmup: []const u8,
    fixture: []const u8,
    rows: u16,
    cols: u16,
    history_capacity: u16,
    chunk_bytes: usize,
    runs: RunCount,
) !WorkloadResult {
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

        try feedServiceChunks(&terminal, warmup, chunk_bytes);
        counting.resetWindow();
        const start = nowNs(io);
        try feedServiceChunks(&terminal, fixture, chunk_bytes);
        const end = nowNs(io);
        if (counting.window_alloc_count != 0)
            return error.SteadyStateAllocation;
        observations[@intCast(i)] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
        };
    }
    return try summarizeObservations(
        base_allocator,
        name,
        byteCount64(fixture),
        observations,
    );
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
            0,
        );
        defer terminal.deinit();
        counting.resetWindow();
        const start = nowNs(io);
        var j: RunCount = 0;
        while (j < bursts_per_run) : (j += 1) {
            try feed(&terminal, burst);
        }
        const end = nowNs(io);
        if (counting.window_alloc_count != 0)
            return error.SteadyStateAllocation;
        observations[@intCast(i)] = .{
            .ns = end - start,
            .alloc_count = counting.window_alloc_count,
            .alloc_bytes = counting.window_alloc_bytes,
            .peak_live_bytes = counting.window_peak_live_bytes,
        };
    }
    return try summarizeObservations(base_allocator, "mixed_interactive", @as(u64, bursts_per_run) * byteCount64(burst), observations);
}

fn printTextResult(result: WorkloadResult) void {
    const median_ms = @as(f64, @floatFromInt(result.median_ns)) / 1_000_000.0;
    const max_ms = @as(f64, @floatFromInt(result.max_ns)) / 1_000_000.0;

    std.debug.print("workload={s}\n", .{result.name});
    std.debug.print("runs={d}\n", .{result.runs});
    std.debug.print("bytes_per_run={d}\n", .{result.bytes_per_run});
    std.debug.print("median_ms={d:.3}\n", .{median_ms});
    std.debug.print("max_ms={d:.3}\n", .{max_ms});
    std.debug.print("throughput_mib_s={d:.2}\n", .{result.throughputMibS()});
    std.debug.print("median_alloc_count={d}\n", .{result.median_alloc_count});
    std.debug.print("median_alloc_bytes={d}\n", .{result.median_alloc_bytes});
    std.debug.print("median_peak_live_bytes={d}\n", .{result.median_peak_live_bytes});
    std.debug.print("---\n", .{});
}

fn printNdjsonResult(result: WorkloadResult) void {
    std.debug.print(
        "{{\"type\":\"howl_vt_benchmark\",\"schema\":1,\"workload\":\"{s}\",\"runs\":{d}," ++
            "\"bytes_per_run\":{d},\"median_ns\":{d},\"max_ns\":{d},\"throughput_mib_s\":{d:.3}," ++
            "\"median_alloc_count\":{d},\"median_alloc_bytes\":{d},\"median_peak_live_bytes\":{d}}}\n",
        .{
            result.name,
            result.runs,
            result.bytes_per_run,
            result.median_ns,
            result.max_ns,
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
    std.debug.print("usage: howl-vt-benchmark [--runs N] [--text]\n", .{});
}

fn parseOptions(args_vector: std.process.Args.Vector) !Options {
    var args = std.process.Args.Iterator.init(.{ .vector = args_vector });
    std.debug.assert(args.next() != null);
    var options = Options{};
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            usage();
            return error.HelpRequested;
        } else if (std.mem.eql(u8, arg, "--text")) {
            options.format = .text;
        } else if (std.mem.eql(u8, arg, "--runs")) {
            const value = args.next() orelse return error.InvalidArgs;
            options.runs = @max(try std.fmt.parseInt(RunCount, value, 10), 1);
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
    const options = parseOptions(init.minimal.args.vector) catch |err| switch (err) {
        error.HelpRequested => return,
        else => return err,
    };
    const runs = options.runs;

    const ascii_overwrite = try buildAsciiOverwriteFixture(allocator);
    defer allocator.free(ascii_overwrite);
    const ascii_scroll = try buildAsciiScrollFixture(allocator);
    defer allocator.free(ascii_scroll);
    const unicode_overwrite = try buildUnicodeOverwriteFixture(allocator);
    defer allocator.free(unicode_overwrite);
    const csi_fixture = try buildCsiFixture(allocator);
    defer allocator.free(csi_fixture);
    const linefeed_scroll = try buildLineFeedScrollFixture(allocator);
    defer allocator.free(linefeed_scroll);

    const ascii_overwrite_result = try runStreamWorkload(
        init.io,
        allocator,
        "ascii_overwrite",
        ascii_overwrite,
        40,
        120,
        0,
        runs,
    );
    const unicode_overwrite_result = try runStreamWorkload(
        init.io,
        allocator,
        "unicode_overwrite",
        unicode_overwrite,
        40,
        120,
        0,
        runs,
    );
    const ascii_scroll_no_history = try runStreamWorkload(
        init.io,
        allocator,
        "ascii_scroll_history0",
        ascii_scroll,
        40,
        120,
        0,
        runs,
    );
    const ascii_scroll_cold_history = try runStreamWorkload(
        init.io,
        allocator,
        "ascii_scroll_history4096_cold",
        ascii_scroll,
        40,
        120,
        4_096,
        runs,
    );
    const ascii_scroll_warm_history = try runWarmStreamWorkload(
        init.io,
        allocator,
        "ascii_scroll_history4096_warm",
        ascii_scroll,
        ascii_scroll,
        40,
        120,
        4_096,
        runs,
    );
    const linefeed_no_history = try runStreamWorkload(
        init.io,
        allocator,
        "linefeed_scroll_history0",
        linefeed_scroll,
        40,
        120,
        0,
        runs,
    );
    const linefeed_warm_history = try runWarmStreamWorkload(
        init.io,
        allocator,
        "linefeed_scroll_history4096_warm",
        linefeed_scroll,
        linefeed_scroll,
        40,
        120,
        4_096,
        runs,
    );
    const service_scroll_warm_history = try runWarmServiceWorkload(
        init.io,
        allocator,
        "service16k_ascii_scroll_history4096_warm",
        ascii_scroll,
        ascii_scroll,
        24,
        80,
        4_096,
        16 * 1024,
        runs,
    );
    const csi_result = try runStreamWorkload(
        init.io,
        allocator,
        "csi_screen_ops",
        csi_fixture,
        40,
        120,
        0,
        runs,
    );
    const mixed_result = try runMixedInteractiveWorkload(init.io, allocator, runs);

    if (options.format == .text) {
        std.debug.print("howl_vt_benchmark_v1\n", .{});
        std.debug.print("runs={d}\n", .{runs});
        std.debug.print("---\n", .{});
    }

    printResult(ascii_overwrite_result, options.format);
    printResult(unicode_overwrite_result, options.format);
    printResult(ascii_scroll_no_history, options.format);
    printResult(ascii_scroll_cold_history, options.format);
    printResult(ascii_scroll_warm_history, options.format);
    printResult(linefeed_no_history, options.format);
    printResult(linefeed_warm_history, options.format);
    printResult(service_scroll_warm_history, options.format);
    printResult(csi_result, options.format);
    printResult(mixed_result, options.format);
}
