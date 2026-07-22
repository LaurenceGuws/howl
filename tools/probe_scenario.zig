//! Runs one deterministic PTY-to-render-preparation scrolling measurement.

const std = @import("std");
const howl_frame = @import("howl_frame");
const howl_probe = @import("howl_probe");
const howl_pty = @import("howl_pty");
const howl_render = @import("howl_render");
const howl_vt = @import("howl_vt");
const paths = @import("probe_paths");

const rows: u16 = 24;
const cols: u16 = 80;
const history_rows: u16 = 2_048;
const baseline_events: usize = 2_048;
const read_timeout_ms: i32 = 1_000;
const idle_limit: u8 = 10;
const scroll_command =
    \\i=0
    \\while [ $i -lt 20000 ]; do
    \\  printf '\033[3%dmrow-%04d abcdefghijklmnopqrstuvwxyz 0123456789\033[0m\r\n' $((i % 8)) "$i"
    \\  i=$((i + 1))
    \\done
;

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(arguments);
    const output = if (arguments.len == 2) arguments[1] else "howl-probe.jsonl";
    if (arguments.len > 2) return error.InvalidArguments;

    try howl_probe.start(init.io, output);
    var probe_stopped = false;
    defer if (!probe_stopped) stopAfterFailure();

    const baseline_start = std.Io.Clock.awake.now(init.io);
    for (0..baseline_events) |_| howl_probe.emit(.scenario, .producer_baseline, .{});
    const baseline_duration_ns: u64 = @intCast(
        baseline_start.durationTo(std.Io.Clock.awake.now(init.io)).toNanoseconds(),
    );
    howl_probe.emit(.scenario, .producer_baseline, .{
        .duration_ns = baseline_duration_ns,
        .count = baseline_events,
    });

    if (howl_probe.enabled) try runPipeline(init.gpa, init.io);

    const summary = try howl_probe.stop();
    probe_stopped = true;
    var stdout_buffer: [512]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print(
        "probe enabled={} producer_ns={d} event_bytes={d} queue_bytes={d} " ++
            "events={d} dropped={d} high_water={d}/{d} records={d} samples={d} output={s}\n",
        .{
            howl_probe.enabled,
            baseline_duration_ns / baseline_events,
            howl_probe.event_bytes,
            howl_probe.queue_bytes,
            summary.accepted,
            summary.dropped,
            summary.high_water,
            howl_probe.queue_capacity,
            summary.records,
            summary.samples,
            output,
        },
    );
    try stdout.flush();
}

fn stopAfterFailure() void {
    const summary = howl_probe.stop() catch return;
    std.mem.doNotOptimizeAway(summary);
}

fn runPipeline(allocator: std.mem.Allocator, io: std.Io) !void {
    var transport = try howl_pty.Owned.init(allocator, "/bin/sh", scroll_command, null);
    defer transport.deinit();
    try transport.start(cols, rows);

    var terminal = try howl_vt.Terminal.initWithHistory(allocator, rows, cols, history_rows);
    defer terminal.deinit();
    var publisher = try howl_frame.Publisher.init(allocator, io, rows, cols);
    defer publisher.deinit();
    var render = try howl_render.Renderer.init(allocator, .{
        .primary = paths.font,
        .pixel_height = 18,
    });
    defer render.deinit();

    howl_probe.emit(.scenario, .thread_start, .{});
    var buffer: [16 * 1_024]u8 = undefined;
    var idle: u8 = 0;
    var render_generation: u64 = 0;
    while (idle < idle_limit) {
        switch (try transport.waitReadable(read_timeout_ms)) {
            .ready => {},
            .timeout => {
                idle += 1;
                continue;
            },
            .canceled => break,
        }
        const read_start = howl_probe.now();
        const count = transport.read(&buffer) catch |failure| switch (failure) {
            error.EndOfStream => break,
            error.Interrupted, error.WouldBlock => continue,
            else => return failure,
        };
        const read_end = howl_probe.now();
        idle = 0;
        howl_probe.emit(.scenario, .pty_read, .{
            .duration_ns = read_end -| read_start,
            .bytes = count,
        });

        const feed_start = howl_probe.now();
        const summary = try terminal.feed(buffer[0..count]);
        const feed_end = howl_probe.now();
        howl_probe.emit(.scenario, .vt_feed, .{
            .duration_ns = feed_end -| feed_start,
            .bytes = count,
            .count = 1,
            .flags = @intFromBool(summary.state_changed) |
                @as(u16, @intFromBool(summary.title_changed)) << 1 |
                @as(u16, @intFromBool(summary.icon_changed)) << 2 |
                @as(u16, @intFromBool(summary.history_lost)) << 3,
        });

        const surface = terminal.surfaceSnapshot();
        const publish_start = howl_probe.now();
        const publication = try publisher.publish(surface, 1, .{
            .width = render.metrics().cell_width,
            .height = render.metrics().cell_height,
        });
        const publish_end = howl_probe.now();
        switch (publication) {
            .saturated => {
                howl_probe.emit(.scenario, .frame_saturated, .{
                    .duration_ns = publish_end -| publish_start,
                });
                continue;
            },
            .published => |generation| {
                if (!terminal.ackSurface(surface.snapshot_seq)) return error.SurfaceAcknowledge;
                howl_probe.emit(.scenario, .frame_publish, .{
                    .duration_ns = publish_end -| publish_start,
                    .generation = generation,
                });
            },
        }

        var borrowed = publisher.borrowNewest() orelse return error.FrameUnavailable;
        const dirty_rows = countDirtyRows(borrowed.frame.damage);
        render_generation += 1;
        const prepare_start = howl_probe.now();
        const prepared = try render.prepare(
            render_generation,
            @as(u32, borrowed.frame.cols) * render.metrics().cell_width,
            @as(u32, borrowed.frame.rows) * render.metrics().cell_height,
            &.{.{
                .x = 0,
                .y = 0,
                .width = @as(u32, borrowed.frame.cols) * render.metrics().cell_width,
                .height = @as(u32, borrowed.frame.rows) * render.metrics().cell_height,
                .frame = borrowed.frame,
            }},
        );
        const prepare_end = howl_probe.now();
        howl_probe.emit(.scenario, .render_prepare, .{
            .duration_ns = prepare_end -| prepare_start,
            .bytes = prepared.cache_bytes,
            .count = prepared.cells,
            .generation = render_generation,
            .auxiliary = prepared.glyphs,
            .detail = packPair(prepared.cache_hits, prepared.cache_misses),
            .flags = @intFromBool(borrowed.frame.damage.full),
        });
        const release_start = howl_probe.now();
        const pending = try borrowed.release();
        const release_end = howl_probe.now();
        howl_probe.emit(.scenario, .frame_borrow_release, .{
            .duration_ns = release_end -| release_start,
            .count = dirty_rows,
            .generation = render_generation,
            .flags = @intFromBool(pending),
        });
    }
}

fn countDirtyRows(damage: howl_frame.Damage) u64 {
    if (damage.full) return damage.rows.len;
    var count: u64 = 0;
    for (damage.rows) |row| count += @intFromBool(row.dirty);
    return count;
}

fn packPair(first: usize, second: usize) u64 {
    const left = std.math.cast(u32, first) orelse std.math.maxInt(u32);
    const right = std.math.cast(u32, second) orelse std.math.maxInt(u32);
    return @as(u64, left) << 32 | right;
}

test "pair packing retains both bounded counters" {
    try std.testing.expectEqual(@as(u64, 3) << 32 | 7, packPair(3, 7));
}
