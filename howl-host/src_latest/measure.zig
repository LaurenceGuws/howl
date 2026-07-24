//! Owns removable, child-local aggregate performance measurement.
//!
//! Disabled builds compile every producer operation to a no-op and perform no
//! allocation, file I/O, formatting, thread naming, or failure propagation.
//! Enabled builds retain fixed counters and latency buckets; orderly host
//! teardown writes one best-effort summary after the render thread has joined.

const std = @import("std");
const options = @import("host_options");

/// Selects the private measurement graph at host compile time.
pub const enabled = options.measure;
/// Names the sole ignored orderly-shutdown receipt relative to the host CWD.
pub const output_path = ".zig/work/howl-performance.txt";
const bucket_count = 16;
const cadence_bucket_count = 66;

/// Borrows enabled state or becomes a zero-sized disabled fact.
pub const Reference = if (enabled) *State else void;
/// Allows isolated wake-owner tests to omit enabled measurement state.
pub const OptionalReference = if (enabled) ?*State else void;
/// Retains an enabled monotonic timestamp or no disabled state.
pub const Mark = if (enabled) std.Io.Clock.Timestamp else void;

const AtomicCounter = std.atomic.Value(u64);

/// Classifies the exact purpose of one submitted rectangle.
pub const QuadKind = enum {
    background,
    text,
    decoration,
    image,
    cursor,
    scrollbar,
    present,
};

const WindowCounters = struct {
    wakes: AtomicCounter = .init(0),
    inspections_changed: u64 = 0,
    inspections_clean: u64 = 0,
    inspections_withheld: u64 = 0,
    projected_rows: u64 = 0,
    projected_cells: u64 = 0,
    submits: u64 = 0,
    coalesced: u64 = 0,
    completions: u64 = 0,
    snapshot_cells: u64 = 0,
    snapshot_rows: u64 = 0,
    snapshot_bytes: u64 = 0,
};

const RenderCounters = struct {
    frames: u64 = 0,
    rows_visited: u64 = 0,
    cells_visited: u64 = 0,
    backing_full_repairs: u64 = 0,
    backing_rows_repaired: u64 = 0,
    runs_native: u64 = 0,
    runs_generated: u64 = 0,
    runs_empty: u64 = 0,
    glyphs: u64 = 0,
    cache_comparisons: u64 = 0,
    cache_hits: u64 = 0,
    cache_misses: u64 = 0,
    rasterizations: u64 = 0,
    mask_uploads: u64 = 0,
    mask_upload_bytes: u64 = 0,
    glyph_atlas_allocations: u64 = 0,
    glyph_atlas_evictions: u64 = 0,
    image_uploads: u64 = 0,
    image_upload_bytes: u64 = 0,
    quads: [@typeInfo(QuadKind).@"enum".field_names.len]u64 = @splat(0),
    staged_quads: u64 = 0,
    staged_commands: u64 = 0,
    staged_merges: u64 = 0,
    staged_flushes: u64 = 0,
    cpu_clipped_quads: u64 = 0,
    cpu_discarded_quads: u64 = 0,
    buffer_calls: u64 = 0,
    buffer_bytes: u64 = 0,
    texture_binds: u64 = 0,
    draw_calls: u64 = 0,
    takes: u64 = 0,
    take_generation_gaps: u64 = 0,
    take_generation_gap_max: u64 = 0,
    presented_generation_gaps: u64 = 0,
    presented_generation_gap_max: u64 = 0,
    present_interval_ns: CadenceHistogram = .{},
    prepare_ns: Histogram = .{},
    draw_ns: Histogram = .{},
    swap_ns: Histogram = .{},
    submit_to_complete_ns: Histogram = .{},
    last_present: ?Mark = null,
    last_taken_generation: u64 = 0,
    last_presented_generation: u64 = 0,
};

/// Owns all fixed measurement state for one host window lifetime.
pub const State = struct {
    geometry_width: if (enabled) u64 else void = if (enabled) 0 else {},
    geometry_height: if (enabled) u64 else void = if (enabled) 0 else {},
    cell_width: if (enabled) u64 else void = if (enabled) 0 else {},
    cell_height: if (enabled) u64 else void = if (enabled) 0 else {},
    rows: if (enabled) u64 else void = if (enabled) 0 else {},
    cols: if (enabled) u64 else void = if (enabled) 0 else {},
    window: if (enabled) WindowCounters else void = if (enabled) .{} else {},
    render: if (enabled) RenderCounters else void = if (enabled) .{} else {},

    /// Borrows enabled state without creating disabled runtime storage.
    pub fn ref(self: *State) Reference {
        if (comptime enabled) {
            return self;
        } else {
            return {};
        }
    }

    /// Replaces the newest configured pixel, cell, and grid geometry.
    pub fn geometry(
        reference: Reference,
        width: u32,
        height: u32,
        cell_width: u16,
        cell_height: u16,
        rows: u16,
        cols: u16,
    ) void {
        if (comptime !enabled) return;
        reference.geometry_width = width;
        reference.geometry_height = height;
        reference.cell_width = cell_width;
        reference.cell_height = cell_height;
        reference.rows = rows;
        reference.cols = cols;
    }

    /// Counts one terminal producer notification without blocking.
    pub fn optionalWake(reference: OptionalReference) void {
        if (comptime !enabled) return;
        const state = reference orelse return;
        incrementAtomic(&state.window.wakes, 1);
    }

    /// Counts one completed visual inspection and its sparse projection.
    pub fn inspection(
        reference: Reference,
        changed: bool,
        withheld: bool,
        rows: usize,
        cells: usize,
    ) void {
        if (comptime !enabled) return;
        increment(
            if (changed) &reference.window.inspections_changed else &reference.window.inspections_clean,
            1,
        );
        if (withheld) increment(&reference.window.inspections_withheld, 1);
        increment(&reference.window.projected_rows, std.math.cast(u64, rows) orelse std.math.maxInt(u64));
        increment(&reference.window.projected_cells, std.math.cast(u64, cells) orelse std.math.maxInt(u64));
    }

    /// Counts one admitted renderer submission.
    pub fn submit(reference: Reference) void {
        if (comptime !enabled) return;
        increment(&reference.window.submits, 1);
    }

    /// Counts one coalesced completion notification drained by the window.
    pub fn completion(reference: Reference) void {
        if (comptime !enabled) return;
        increment(&reference.window.completions, 1);
    }

    /// Records one immutable snapshot taken by the render worker.
    pub fn take(reference: Reference, generation: u64) void {
        if (comptime !enabled) return;
        recordGenerationGap(
            &reference.render.take_generation_gaps,
            &reference.render.take_generation_gap_max,
            &reference.render.last_taken_generation,
            generation,
        );
        increment(&reference.render.takes, 1);
    }

    /// Counts exact stale-row snapshot copies and pending replacement.
    pub fn snapshot(
        reference: Reference,
        rows: usize,
        cells: usize,
        bytes: usize,
        coalesced: bool,
    ) void {
        if (comptime !enabled) return;
        increment(&reference.window.snapshot_rows, std.math.cast(u64, rows) orelse std.math.maxInt(u64));
        increment(&reference.window.snapshot_cells, std.math.cast(u64, cells) orelse std.math.maxInt(u64));
        increment(&reference.window.snapshot_bytes, std.math.cast(u64, bytes) orelse std.math.maxInt(u64));
        if (coalesced) increment(&reference.window.coalesced, 1);
    }

    /// Counts one full or sparse retained-backing repair.
    pub fn backing(reference: Reference, full: bool, rows: usize) void {
        if (comptime !enabled) return;
        if (full) increment(&reference.render.backing_full_repairs, 1);
        increment(
            &reference.render.backing_rows_repaired,
            std.math.cast(u64, rows) orelse std.math.maxInt(u64),
        );
    }

    /// Counts one background row scan and its logical cells.
    pub fn visitRow(reference: Reference, cells: usize) void {
        if (comptime !enabled) return;
        increment(&reference.render.rows_visited, 1);
        increment(&reference.render.cells_visited, std.math.cast(u64, cells) orelse std.math.maxInt(u64));
    }

    /// Counts one homogeneous text run, its glyphs, and preparation latency.
    pub fn prepared(
        reference: Reference,
        kind: enum { native, generated, empty },
        glyphs: usize,
        nanoseconds: u64,
    ) void {
        if (comptime !enabled) return;
        increment(switch (kind) {
            .native => &reference.render.runs_native,
            .generated => &reference.render.runs_generated,
            .empty => &reference.render.runs_empty,
        }, 1);
        increment(&reference.render.glyphs, std.math.cast(u64, glyphs) orelse std.math.maxInt(u64));
        reference.render.prepare_ns.record(nanoseconds);
    }

    /// Counts one glyph-cache lookup and exact probed identities.
    pub fn cache(reference: Reference, comparisons: usize, hit: bool) void {
        if (comptime !enabled) return;
        increment(
            &reference.render.cache_comparisons,
            std.math.cast(u64, comparisons) orelse std.math.maxInt(u64),
        );
        increment(if (hit) &reference.render.cache_hits else &reference.render.cache_misses, 1);
    }

    /// Counts one rasterization and any resulting alpha-mask upload.
    pub fn raster(reference: Reference, bytes: usize, uploaded: bool) void {
        if (comptime !enabled) return;
        increment(&reference.render.rasterizations, 1);
        if (uploaded) {
            increment(&reference.render.mask_uploads, 1);
            increment(
                &reference.render.mask_upload_bytes,
                std.math.cast(u64, bytes) orelse std.math.maxInt(u64),
            );
        }
    }

    /// Counts one admitted glyph-atlas texture and whether it replaced one.
    pub fn glyphAtlas(reference: Reference, replaced: bool) void {
        if (comptime !enabled) return;
        increment(&reference.render.glyph_atlas_allocations, 1);
        if (replaced) increment(&reference.render.glyph_atlas_evictions, 1);
    }

    /// Counts one retained RGBA image texture upload.
    pub fn imageUpload(reference: Reference, bytes: usize) void {
        if (comptime !enabled) return;
        increment(&reference.render.image_uploads, 1);
        increment(
            &reference.render.image_upload_bytes,
            std.math.cast(u64, bytes) orelse std.math.maxInt(u64),
        );
    }

    /// Counts one explicit GLES texture bind.
    pub fn textureBind(reference: Reference) void {
        if (comptime !enabled) return;
        increment(&reference.render.texture_binds, 1);
    }

    /// Counts one quad admitted to the bounded renderer staging storage.
    pub fn stagedQuad(reference: Reference, kind: QuadKind) void {
        if (comptime !enabled) return;
        increment(&reference.render.quads[@backingInt(kind)], 1);
        increment(&reference.render.staged_quads, 1);
    }

    /// Counts exact CPU clipping that changed or fully discarded one quad.
    pub fn cpuClip(reference: Reference, changed: bool, discarded: bool) void {
        if (comptime !enabled) return;
        std.debug.assert(!discarded or !changed);
        if (changed) increment(&reference.render.cpu_clipped_quads, 1);
        if (discarded) increment(&reference.render.cpu_discarded_quads, 1);
    }

    /// Counts one staged upload and its exact resulting commands and merges.
    pub fn batch(reference: Reference, commands: usize, merges: usize, bytes: usize) void {
        if (comptime !enabled) return;
        increment(&reference.render.staged_commands, std.math.cast(u64, commands) orelse
            std.math.maxInt(u64));
        increment(&reference.render.staged_merges, std.math.cast(u64, merges) orelse
            std.math.maxInt(u64));
        increment(&reference.render.staged_flushes, 1);
        increment(&reference.render.buffer_calls, 1);
        increment(&reference.render.buffer_bytes, std.math.cast(u64, bytes) orelse std.math.maxInt(u64));
        increment(&reference.render.draw_calls, std.math.cast(u64, commands) orelse
            std.math.maxInt(u64));
    }

    /// Records one swapped frame and its bounded high-level latencies.
    pub fn frame(
        reference: Reference,
        generation: u64,
        presented_at: Mark,
        draw_ns: u64,
        swap_ns: u64,
        submit_to_complete_ns: u64,
    ) void {
        if (comptime !enabled) return;
        recordCadence(
            &reference.render.present_interval_ns,
            &reference.render.last_present,
            presented_at,
        );
        recordGenerationGap(
            &reference.render.presented_generation_gaps,
            &reference.render.presented_generation_gap_max,
            &reference.render.last_presented_generation,
            generation,
        );
        increment(&reference.render.frames, 1);
        reference.render.draw_ns.record(draw_ns);
        reference.render.swap_ns.record(swap_ns);
        reference.render.submit_to_complete_ns.record(submit_to_complete_ns);
    }

    /// Writes one best-effort receipt; I/O failure never changes host cleanup.
    pub fn writeSummary(self: *const State, io: std.Io) void {
        if (comptime !enabled) return;
        self.writeSummaryEnabled(io) catch {};
    }

    fn writeSummaryEnabled(self: *const State, io: std.Io) !void {
        try std.Io.Dir.createDirPath(.cwd(), io, ".zig/work");
        var file = try std.Io.Dir.cwd().createFile(io, output_path, .{});
        defer file.close(io);
        var buffer: [16 * 1024]u8 = undefined;
        var writer = file.writer(io, &buffer);
        const out = &writer.interface;
        try self.writeTo(out);
        try out.flush();
    }

    fn writeTo(self: *const State, out: *std.Io.Writer) !void {
        try out.print(
            "geometry.width={d}\ngeometry.height={d}\ncell.width={d}\ncell.height={d}\nrows={d}\ncols={d}\n",
            .{
                self.geometry_width,
                self.geometry_height,
                self.cell_width,
                self.cell_height,
                self.rows,
                self.cols,
            },
        );
        try writeWindow(out, &self.window);
        try writeRender(out, &self.render);
    }
};

comptime {
    if (!enabled) {
        std.debug.assert(@sizeOf(State) == 0);
        std.debug.assert(@sizeOf(Reference) == 0);
        std.debug.assert(@sizeOf(Mark) == 0);
    }
}

/// Retains fixed exponential microsecond buckets plus exact aggregate latency.
pub const Histogram = struct {
    buckets: [bucket_count]u64 = @splat(0),
    count: u64 = 0,
    total_ns: u64 = 0,
    max_ns: u64 = 0,

    /// Admits one duration into bucket zero through fifteen without allocation.
    pub fn record(self: *Histogram, nanoseconds: u64) void {
        const bucket = bucketFor(nanoseconds);
        increment(&self.buckets[bucket], 1);
        increment(&self.count, 1);
        self.total_ns = std.math.add(u64, self.total_ns, nanoseconds) catch std.math.maxInt(u64);
        self.max_ns = @max(self.max_ns, nanoseconds);
    }
};

// Retains exact one-millisecond cadence buckets through 64 ms plus overflow.
const CadenceHistogram = struct {
    buckets: [cadence_bucket_count]u64 = @splat(0),
    count: u64 = 0,
    total_ns: u64 = 0,
    max_ns: u64 = 0,

    fn record(self: *CadenceHistogram, nanoseconds: u64) void {
        const milliseconds = nanoseconds / std.time.ns_per_ms;
        const bucket = @min(cadence_bucket_count - 1, std.math.cast(
            usize,
            milliseconds,
        ) orelse cadence_bucket_count - 1);
        increment(&self.buckets[bucket], 1);
        increment(&self.count, 1);
        self.total_ns = std.math.add(u64, self.total_ns, nanoseconds) catch
            std.math.maxInt(u64);
        self.max_ns = @max(self.max_ns, nanoseconds);
    }
};

/// Takes one enabled monotonic timestamp or compiles to no disabled work.
pub fn now(io: std.Io) Mark {
    if (comptime enabled) {
        return .now(io, .awake);
    } else {
        return {};
    }
}

/// Returns elapsed enabled nanoseconds or zero in disabled builds.
pub fn elapsed(start: Mark, io: std.Io) u64 {
    if (comptime enabled) {
        const value = start.untilNow(io).raw.nanoseconds;
        return if (value <= 0) 0 else std.math.cast(u64, value) orelse std.math.maxInt(u64);
    } else {
        return 0;
    }
}

fn elapsedBetween(start: Mark, finish: Mark) u64 {
    if (comptime enabled) {
        const value = start.durationTo(finish).raw.nanoseconds;
        return if (value <= 0) 0 else std.math.cast(u64, value) orelse std.math.maxInt(u64);
    } else {
        return 0;
    }
}

fn recordCadence(histogram: *CadenceHistogram, previous: *?Mark, current: Mark) void {
    if (previous.*) |prior| histogram.record(elapsedBetween(prior, current));
    previous.* = current;
}

fn recordGenerationGap(total: *u64, maximum: *u64, previous: *u64, current: u64) void {
    std.debug.assert(current > previous.*);
    if (previous.* != 0) {
        const gap = current - previous.* - 1;
        increment(total, gap);
        maximum.* = @max(maximum.*, gap);
    }
    previous.* = current;
}

fn incrementAtomic(counter: *AtomicCounter, amount: usize) void {
    const value = std.math.cast(u64, amount) orelse std.math.maxInt(u64);
    const previous = counter.fetchAdd(value, .monotonic);
    if (previous > std.math.maxInt(u64) - value) @panic("measurement counter exhausted");
}

fn increment(counter: *u64, amount: u64) void {
    counter.* = std.math.add(u64, counter.*, amount) catch @panic("measurement counter exhausted");
}

fn bucketFor(nanoseconds: u64) usize {
    if (nanoseconds <= 1_000) return 0;
    const micros = (nanoseconds - 1) / 1_000;
    return @min(bucket_count - 1, @as(usize, std.math.log2(micros)) + 1);
}

fn writeWindow(out: *std.Io.Writer, value: *const WindowCounters) !void {
    try out.print(
        "window.wakes={d}\nwindow.inspections_changed={d}\nwindow.inspections_clean={d}\nwindow.inspections_withheld={d}\nwindow.projected_rows={d}\nwindow.projected_cells={d}\nwindow.submits={d}\nwindow.coalesced={d}\nwindow.completions={d}\nwindow.snapshot_rows={d}\nwindow.snapshot_cells={d}\nwindow.snapshot_bytes={d}\n",
        .{
            value.wakes.load(.monotonic),
            value.inspections_changed,
            value.inspections_clean,
            value.inspections_withheld,
            value.projected_rows,
            value.projected_cells,
            value.submits,
            value.coalesced,
            value.completions,
            value.snapshot_rows,
            value.snapshot_cells,
            value.snapshot_bytes,
        },
    );
}

fn writeRender(out: *std.Io.Writer, value: *const RenderCounters) !void {
    const info = @typeInfo(RenderCounters).@"struct";
    inline for (info.field_names, info.field_types) |name, field_type| {
        if (field_type == u64) try out.print("render.{s}={d}\n", .{ name, @field(value, name) });
    }
    inline for (@typeInfo(QuadKind).@"enum".field_names, 0..) |name, index|
        try out.print("render.quad_{s}={d}\n", .{ name, value.quads[index] });
    try writeHistogram(out, "prepare_ns", &value.prepare_ns);
    try writeHistogram(out, "draw_ns", &value.draw_ns);
    try writeHistogram(out, "swap_ns", &value.swap_ns);
    try writeHistogram(out, "submit_to_complete_ns", &value.submit_to_complete_ns);
    try writeCadence(out, "render.present_interval_ns", &value.present_interval_ns);
}

fn writeHistogram(out: *std.Io.Writer, name: []const u8, value: *const Histogram) !void {
    try out.print(
        "render.{s}.count={d}\nrender.{s}.total={d}\nrender.{s}.max={d}\n",
        .{ name, value.count, name, value.total_ns, name, value.max_ns },
    );
    for (value.buckets, 0..) |count, index|
        try out.print("render.{s}.bucket_{d}={d}\n", .{ name, index, count });
}

fn writeCadence(out: *std.Io.Writer, name: []const u8, value: *const CadenceHistogram) !void {
    try out.print(
        "{s}.count={d}\n{s}.total={d}\n{s}.max={d}\n",
        .{ name, value.count, name, value.total_ns, name, value.max_ns },
    );
    for (value.buckets, 0..) |count, index|
        try out.print("{s}.bucket_{d}={d}\n", .{ name, index, count });
}

test "histogram buckets and totals are exact at boundaries" {
    var value = Histogram{};
    value.record(0);
    value.record(1_000);
    value.record(1_001);
    value.record(2_001);
    try std.testing.expectEqual(@as(u64, 4), value.count);
    try std.testing.expectEqual(@as(u64, 4_002), value.total_ns);
    try std.testing.expectEqual(@as(u64, 2), value.buckets[0]);
    try std.testing.expectEqual(@as(u64, 1), value.buckets[1]);
    try std.testing.expectEqual(@as(u64, 1), value.buckets[2]);
    try std.testing.expectEqual(@as(u64, 2_001), value.max_ns);
}

test "cadence buckets retain millisecond boundaries and overflow" {
    var value = CadenceHistogram{};
    value.record(0);
    value.record(std.time.ns_per_ms - 1);
    value.record(std.time.ns_per_ms);
    value.record(64 * std.time.ns_per_ms);
    value.record(65 * std.time.ns_per_ms);
    try std.testing.expectEqual(@as(u64, 5), value.count);
    try std.testing.expectEqual(@as(u64, 2), value.buckets[0]);
    try std.testing.expectEqual(@as(u64, 1), value.buckets[1]);
    try std.testing.expectEqual(@as(u64, 1), value.buckets[64]);
    try std.testing.expectEqual(@as(u64, 1), value.buckets[65]);
    try std.testing.expectEqual(@as(u64, 65 * std.time.ns_per_ms), value.max_ns);
}

test "generation gaps count only superseded identities" {
    var total: u64 = 0;
    var maximum: u64 = 0;
    var previous: u64 = 0;
    recordGenerationGap(&total, &maximum, &previous, 4);
    recordGenerationGap(&total, &maximum, &previous, 5);
    recordGenerationGap(&total, &maximum, &previous, 9);
    try std.testing.expectEqual(@as(u64, 3), total);
    try std.testing.expectEqual(@as(u64, 3), maximum);
    try std.testing.expectEqual(@as(u64, 9), previous);
}

test "disabled reference and producers have no retained runtime state" {
    if (enabled) return error.SkipZigTest;
    var state = State{};
    const reference = state.ref();
    State.geometry(reference, 1, 2, 3, 4, 5, 6);
    State.optionalWake(if (enabled) reference else {});
    State.inspection(reference, true, true, 7, 8);
    State.submit(reference);
    State.completion(reference);
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(Reference));
    try std.testing.expectEqual(@as(usize, 0), @sizeOf(State));
}

test "enabled summary exposes fixed geometry counters and histogram vocabulary" {
    if (!enabled) return error.SkipZigTest;
    var state = State{};
    const reference = state.ref();
    State.geometry(reference, 960, 600, 9, 23, 26, 106);
    State.inspection(reference, true, false, 2, 17);
    State.snapshot(reference, 26, 2_756, 44_096, true);
    State.prepared(reference, .native, 4, 2_000);
    State.stagedQuad(reference, .text);
    State.stagedQuad(reference, .text);
    State.cpuClip(reference, true, false);
    State.cpuClip(reference, false, true);
    State.glyphAtlas(reference, true);
    State.batch(reference, 1, 1, 384);
    const frame_at = now(std.testing.io);
    State.take(reference, 1);
    State.frame(reference, 1, frame_at, 3_000, 4_000, 9_000);
    var bytes: [16 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&bytes);
    try state.writeTo(&writer);
    const summary = bytes[0..writer.end];
    try std.testing.expect(std.mem.indexOf(u8, summary, "rows=26\ncols=106\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "window.projected_cells=17\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "window.coalesced=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "window.snapshot_bytes=44096\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "render.quad_text=2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "render.staged_commands=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "render.staged_merges=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "render.cpu_clipped_quads=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "render.cpu_discarded_quads=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "render.glyph_atlas_allocations=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "render.glyph_atlas_evictions=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "render.buffer_calls=1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "render.buffer_bytes=384\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, summary, "render.draw_ns.count=1\n") != null);
}
