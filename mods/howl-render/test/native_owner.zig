//! Exercises the public optional owner with canonical VT and real Text.
const std = @import("std");
const owner = @import("howl_render_owner_native");
const c = owner.c;
const vt = @import("howl_vt_native");
const source = vt.observation;
const render = @import("howl_render");
const native = @import("howl_render_native");
const font_path = @import("test_fonts").primary_font;
const font_bytes = @embedFile("font_data");
fn config() c.hrc_config {
    var value = std.mem.zeroes(c.hrc_config);
    value.fonts[0] = .{ .kind = c.HRC_FONT_PATH, .reserved = @splat(0), .primary = .{ .data = font_path.ptr, .len = font_path.len }, .fallbacks = null, .fallback_count = 0 };
    value.pixel_size = 18;
    value.max_sequence_scalars = 16;
    value.shape_entries = 256;
    value.shape_scalars = 1024;
    value.shape_glyphs = 1024;
    value.shaped_capacity = 1024;
    value.raster_bytes = 65536;
    value.stroke_points = .{ 0.001, 1, 1.5, 2 };
    value.dpi_x_numerator = 96;
    value.dpi_y_numerator = 96;
    value.dpi_x_denominator = 1;
    value.dpi_y_denominator = 1;
    value.atlas_width = 256;
    value.atlas_height = 256;
    value.atlas_entries = 256;
    value.command_capacity = 4;
    value.command_limit = 4096;
    value.frame_pixel_limit = 131072;
    value.frame_buffer_limit = 3;
    return value;
}
fn destroy(value: *owner.Owner) void {
    // zig-audit: acknowledge catch_unreachable
    // reason: Each proof closes every opened buffer first; a busy test teardown is an invariant failure.
    owner.destroy(value) catch unreachable;
}
fn close(value: *owner.Buffer) void {
    // zig-audit: acknowledge catch_unreachable
    // reason: Each proof releases its successful lease before buffer teardown; busy means the proof violated ownership.
    owner.close(value) catch unreachable;
}
fn release(value: *owner.Buffer) void {
    // zig-audit: acknowledge catch_unreachable
    // reason: Deferred cleanup is installed only after a successful capture and consumes exactly that one lease.
    owner.release(value) catch unreachable;
}
fn terminal() !*vt.owner.Owner {
    return vt.owner.create(std.testing.allocator, &.{ .rows = 3, .columns = 12, .history_rows = 8, .reserved = 0, .cell_width = 8, .cell_height = 16 });
}
fn feed(value: *vt.owner.Owner, bytes: []const u8) !void {
    var at: usize = 0;
    while (at < bytes.len) {
        const progress = try vt.owner.feed(value, bytes[at..], 17);
        try std.testing.expect(progress.consumed != 0);
        at += progress.consumed;
    }
}
fn setup(allocator: std.mem.Allocator, value: *vt.owner.Owner, options: *const c.hrc_config) !*owner.Owner {
    const reader = try vt.owner.openObservation(value);
    defer source.release(reader);
    return owner.create(allocator, options, reader);
}
fn capture(frame: *owner.Buffer, history: u32, residency: []const c.hrc_residency) !c.hrc_frame_view {
    const info = try owner.capture(frame, history, residency);
    const result = try owner.read(frame);
    try std.testing.expectEqualDeep(info, result.info);
    return result;
}
fn records(comptime T: type, ptr: [*c]const T, count: u32) []const T {
    return if (count == 0) &.{} else ptr[0..count];
}
fn payloadDigest(view: c.hrc_frame_view) u64 {
    var hash = std.hash.Wyhash.init(0);
    for (records(c.hrc_command, view.commands, view.info.command_count)) |record| hash.update(std.mem.asBytes(&record));
    for (records(c.hrc_removal, view.removals, view.info.removal_count)) |record| hash.update(std.mem.asBytes(&record));
    for (records(c.hrc_upload, view.uploads, view.info.upload_count)) |upload| {
        hash.update(std.mem.asBytes(&upload.info));
        hash.update(upload.pixels[0..upload.pixel_len]);
    }
    return hash.final();
}
fn digest(view: c.hrc_frame_view) u64 {
    var hash = std.hash.Wyhash.init(payloadDigest(view));
    hash.update(std.mem.asBytes(&view.info));
    return hash.final();
}
fn resident(view: c.hrc_frame_view, output: *[8]c.hrc_residency) []c.hrc_residency {
    for (records(c.hrc_upload, view.uploads, view.info.upload_count), 0..) |upload, i| output[i] = .{
        .resource = upload.info.resource,
        .generation = upload.info.generation,
        .width = upload.info.width,
        .height = upload.info.height,
        .format = upload.info.format,
        ._reserved = @splat(0),
    };
    return output[0..view.info.upload_count];
}

test "constructor and four canonical style/fallback owners unwind every allocation prefix" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, construction, .{});
}
fn construction(allocator: std.mem.Allocator) !void {
    const value = try terminal();
    defer vt.owner.destroy(value);
    var options = config();
    const fallback = [_]c.hrc_bytes{.{ .data = font_bytes.ptr, .len = font_bytes.len }};
    for (&options.fonts) |*font| font.* = .{ .kind = c.HRC_FONT_MEMORY, .reserved = @splat(0), .primary = .{ .data = font_bytes.ptr, .len = font_bytes.len }, .fallbacks = &fallback, .fallback_count = fallback.len };
    const renderer = try setup(allocator, value, &options);
    defer destroy(renderer);
    const cell = owner.cellSize(renderer);
    try std.testing.expect(cell.width > 0 and cell.height > 0 and cell.reserved == 0);
}

test "frame buffers pin parents between leases and never evict at the exact limit" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    var options = config();
    options.frame_buffer_limit = 2;
    const renderer = try setup(std.testing.allocator, value, &options);
    defer destroy(renderer);
    const a = try owner.open(renderer);
    var a_live = true;
    defer if (a_live) close(a);
    const b = try owner.open(renderer);
    defer close(b);
    try std.testing.expectError(error.ResourceLimit, owner.open(renderer));
    try std.testing.expectError(error.Busy, owner.destroy(renderer));
    try std.testing.expectError(error.NoFrame, owner.read(a));
    try std.testing.expectError(error.NoFrame, owner.release(a));
    const first = try capture(a, 0, &.{});
    const before = digest(first);
    try std.testing.expectError(error.Busy, owner.close(a));
    try std.testing.expectError(error.Busy, owner.capture(a, 0, &.{}));
    try std.testing.expectEqual(before, digest(try owner.read(a)));
    try owner.release(a);
    try std.testing.expectError(error.Busy, owner.destroy(renderer));
    try owner.close(a);
    a_live = false;
    const replacement = try owner.open(renderer);
    defer close(replacement);
}

test "held frames survive feed resize reset animation source closure and newer buffers" {
    const value = try terminal();
    var live = true;
    defer if (live) vt.owner.destroy(value);
    try feed(value, "A\xcc\x81界\x1b[2;1H\x1b#6wide\x1b[3;1Htail");
    const renderer = try setup(std.testing.allocator, value, &config());
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const b = try owner.open(renderer);
    defer close(b);
    const first = try capture(a, 0, &.{});
    const before = digest(first);
    defer release(a);
    try feed(value, "\r\nnew1\r\nnew2\r\nnew3");
    try vt.owner.resize(value, 4, 14, 9, 17);
    const second = try capture(b, std.math.maxInt(u32), &.{});
    try std.testing.expect(second.info.history_offset <= second.info.history_count);
    try std.testing.expect(second.info.surface_width == 14 * second.info.cell_width);
    try owner.release(b);
    vt.owner.reset(value);
    // zig-audit: acknowledge discard
    // reason: Exercise canonical animation service while copied old frames remain leased.
    _ = vt.owner.serviceAnimations(value, 999);
    const third = try capture(b, 0, &.{});
    try std.testing.expect(third.info.command_count != 0);
    try owner.release(b);
    vt.owner.destroy(value);
    live = false;
    try std.testing.expectError(error.SourceClosed, owner.capture(b, 0, &.{}));
    try std.testing.expectError(error.NoFrame, owner.read(b));
    try std.testing.expectEqual(before, digest(try owner.read(a)));
}

test "exact residency suppresses atlas and rgba while stale truth reuploads without same-id removal" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    try feed(value, "A\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1,q=2;AQIDBA==\x1b\\");
    const renderer = try setup(std.testing.allocator, value, &config());
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const first = try capture(a, 0, &.{});
    try std.testing.expectEqual(@as(u32, 2), first.info.upload_count);
    var storage: [8]c.hrc_residency = undefined;
    const truth = resident(first, &storage);
    var rgba = false;
    var alpha = false;
    for (records(c.hrc_upload, first.uploads, first.info.upload_count)) |upload| {
        if (upload.info.format == c.HRC_RGBA8) {
            rgba = true;
            try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, upload.pixels[0..upload.pixel_len]);
        } else alpha = true;
    }
    try std.testing.expect(rgba and alpha);
    try owner.release(a);
    const exact = try capture(a, 0, truth);
    try std.testing.expectEqual(@as(u32, 0), exact.info.upload_count);
    const commands = exact.info.command_count;
    try owner.release(a);
    for (truth) |*entry| {
        entry.generation +%= 1;
        entry.width += 1;
        entry.format = if (entry.format == c.HRC_ALPHA8) c.HRC_RGBA8 else c.HRC_ALPHA8;
    }
    const stale = try capture(a, 0, truth);
    try std.testing.expectEqual(@as(u32, 2), stale.info.upload_count);
    try std.testing.expectEqual(commands, stale.info.command_count);
    for (records(c.hrc_removal, stale.removals, stale.info.removal_count)) |removal| {
        for (records(c.hrc_upload, stale.uploads, stale.info.upload_count)) |upload| try std.testing.expect(removal.resource != upload.info.resource);
    }
    try owner.release(a);
    const failed_gpu_upload = try capture(a, 0, &.{});
    try std.testing.expectEqual(@as(u32, 2), failed_gpu_upload.info.upload_count);
    try owner.release(a);
}

test "partial glyph residency admits only missing pixels within the native frame bound" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    var options = config();
    const color_font = @import("test_fonts").colour_font;
    const fallbacks = [_]c.hrc_bytes{.{ .data = color_font.ptr, .len = color_font.len }};
    options.fonts[0].fallbacks = &fallbacks;
    options.fonts[0].fallback_count = fallbacks.len;
    const plane_bytes = @as(usize, options.atlas_width) * options.atlas_height;
    options.frame_pixel_limit = plane_bytes * 4;
    try feed(value, "\x1b[?25l\xf0\x9f\x98\x80");
    const renderer = try setup(std.testing.allocator, value, &options);
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const color = try capture(a, 0, &.{});
    defer release(a);
    try std.testing.expectEqual(@as(u32, 1), color.info.upload_count);
    try std.testing.expectEqual(@as(u32, c.HRC_RGBA8), color.uploads[0].info.format);
    try std.testing.expectEqual(plane_bytes * 4, color.uploads[0].pixel_len);
    const held_digest = digest(color);
    var storage: [8]c.hrc_residency = undefined;
    const truth = resident(color, &storage);

    try feed(value, "\x1b[1;4HA");
    const b = try owner.open(renderer);
    defer close(b);
    {
        const alpha = try capture(b, 0, truth);
        defer release(b);
        try std.testing.expectEqual(@as(u32, 1), alpha.info.upload_count);
        try std.testing.expectEqual(@as(u32, c.HRC_ALPHA8), alpha.uploads[0].info.format);
        try std.testing.expectEqual(plane_bytes, alpha.uploads[0].pixel_len);
        try std.testing.expectEqual(held_digest, digest(try owner.read(a)));
    }
    // Losing both resources still requires five planes; never bypass the limit.
    try std.testing.expectError(error.ResourceLimit, owner.capture(b, 0, &.{}));
    try std.testing.expectError(error.NoFrame, owner.read(b));
    const recovered = try capture(b, 0, truth);
    defer release(b);
    try std.testing.expectEqual(@as(u32, 1), recovered.info.upload_count);
    try std.testing.expectEqual(held_digest, digest(try owner.read(a)));
}

test "capture allocation prefixes publish no partial frame and preserve held bytes" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, captureCampaign, .{});
}
fn captureCampaign(allocator: std.mem.Allocator) !void {
    const value = try terminal();
    defer vt.owner.destroy(value);
    try feed(value, "A\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1,q=2;AQIDBA==\x1b\\");
    const renderer = try setup(allocator, value, &config());
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const held = try capture(a, 0, &.{});
    defer release(a);
    const before = digest(held);
    const b = try owner.open(renderer);
    defer close(b);
    try feed(value, "\x1b[2;1Hnewer glyphs");
    // The independent VT allocator is not part of this campaign: every failed
    // allocation belongs to Render construction, update or private output growth.
    const result = capture(b, 0, &.{}) catch |err| {
        try std.testing.expectError(error.NoFrame, owner.read(b));
        try std.testing.expectEqual(before, digest(try owner.read(a)));
        return err;
    };
    try std.testing.expect(result.info.command_count != 0);
    try std.testing.expectEqual(before, digest(try owner.read(a)));
    try owner.release(b);
}

test "warmed available buffer reuses payload capacity with allocator disabled" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    try feed(value, "A");
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const renderer = try setup(failing.allocator(), value, &config());
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const first = try capture(a, 0, &.{});
    const before = payloadDigest(first);
    try owner.release(a);
    failing.fail_index = failing.alloc_index;
    failing.resize_fail_index = failing.resize_index;
    const second = try capture(a, 0, &.{});
    defer release(a);
    try std.testing.expectEqual(before, payloadDigest(second));
}

test "source retirement precedes native font access and reference limit is recoverable" {
    const value = try terminal();
    var live = true;
    defer if (live) vt.owner.destroy(value);
    const reader = try vt.owner.openObservation(value);
    defer source.release(reader);
    var refs: [source.maximum_references - 2]*source.Reader = undefined;
    var count: usize = 0;
    defer for (refs[0..count]) |extra| source.release(extra);
    for (&refs) |*extra| {
        extra.* = try source.retain(reader);
        count += 1;
    }
    try std.testing.expectError(error.ResourceLimit, owner.create(std.testing.allocator, &config(), reader));
    count -= 1;
    source.release(refs[count]);
    const renderer = try owner.create(std.testing.allocator, &config(), reader);
    try owner.destroy(renderer);
    vt.owner.destroy(value);
    live = false;
    var options = config();
    options.fonts[0].primary = .{ .data = "nonexistent-font".ptr, .len = "nonexistent-font".len };
    try std.testing.expectError(error.SourceClosed, owner.create(std.testing.allocator, &options, reader));
}

test "configuration and nested ranges reject before allocation or slice formation" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    const reader = try vt.owner.openObservation(value);
    defer source.release(reader);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var options = config();
    options.reserved3 = 1;
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &options, reader));
    options = config();
    options.frame_buffer_limit = c.HRC_MAX_FRAME_BUFFERS + 1;
    try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &options, reader));
    options = config();
    options.command_limit = c.HRC_MAX_FRAME_COMMANDS + 1;
    try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &options, reader));
    options = config();
    options.fonts[0].primary.len = c.HRC_MAX_FONT_PATH_BYTES + 1;
    try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &options, reader));
    options = config();
    // zig-audit: acknowledge ptr_from_int
    // reason: This hostile range is rejected by address-end admission before dereference.
    options.fonts[0].primary.data = @ptrFromInt(std.math.maxInt(usize) - 2);
    options.fonts[0].primary.len = 4;
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &options, reader));
    options = config();
    options.fonts[1].primary.len = 1;
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &options, reader));
    options = config();
    options.stroke_points[0] = std.math.nan(f32);
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &options, reader));
    options = config();
    options.dpi_x_denominator = 0;
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &options, reader));
    options = config();
    try std.testing.expectError(error.OutOfMemory, owner.create(failing.allocator(), &options, reader));
}

test "real backend release hands immutable bytes back to producer for reuse" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    try feed(value, "first");
    const renderer = try setup(std.testing.allocator, value, &config());
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const b = try owner.open(renderer);
    defer close(b);
    const first = try capture(a, 0, &.{});
    var gate = std.atomic.Value(bool).init(false);
    var bad = std.atomic.Value(bool).init(false);
    const Worker = struct {
        fn run(frame: *owner.Buffer, expected: u64, ready: *std.atomic.Value(bool), failed: *std.atomic.Value(bool)) void {
            while (!ready.load(.acquire)) std.atomic.spinLoopHint();
            const view = owner.read(frame) catch {
                failed.store(true, .release);
                return;
            };
            if (digest(view) != expected) failed.store(true, .release);
            owner.release(frame) catch failed.store(true, .release);
        }
    };
    const worker = try std.Thread.spawn(.{}, Worker.run, .{ a, digest(first), &gate, &bad });
    var joined = false;
    defer if (!joined) {
        gate.store(true, .release);
        worker.join();
    };
    try feed(value, "\r\nsecond");
    const second = try capture(b, 0, &.{});
    try std.testing.expect(second.info.command_count != 0);
    try owner.release(b);
    gate.store(true, .release);
    // No done flag mediates payload reuse: only acquire admission of available
    // pairs with the backend's final release transition.
    var captured = false;
    for (0..10_000_000) |_| {
        const next = owner.capture(a, 0, &.{}) catch |err| switch (err) {
            error.Busy => {
                std.atomic.spinLoopHint();
                continue;
            },
            else => return err,
        };
        try std.testing.expect(next.command_count != 0);
        captured = true;
        break;
    }
    try std.testing.expect(captured);
    worker.join();
    joined = true;
    try std.testing.expect(!bad.load(.acquire));
    try owner.release(a);
}

test "standalone complete commands equal direct canonical composition across terminal geometry" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    const options = config();
    const renderer = try setup(std.testing.allocator, value, &options);
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const font = try render.text.FontSet.init(std.testing.allocator, .{ .primary = font_path, .size = .{ .pixels = options.pixel_size } });
    defer font.deinit();
    const metrics = font.metrics();
    const core = try render.terminal.initPrivate(std.testing.allocator, .{ .regular = font }, .{
        .cell_size = .{ .width = metrics.advance_width, .height = metrics.line_height },
        .box_drawing = .{ .stroke_points = options.stroke_points, .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = options.shape_entries, .scalar_capacity = options.shape_scalars, .glyph_capacity = options.shape_glyphs, .max_sequence_scalars = options.max_sequence_scalars },
        .atlas = .{ .width = options.atlas_width, .height = options.atlas_height, .gap = options.atlas_gap, .entry_capacity = options.atlas_entries },
        .shaped_capacity = options.shaped_capacity,
        .raster_bytes = options.raster_bytes,
        .command_capacity = options.command_capacity,
        .command_limit = options.command_limit,
    });
    defer render.terminal.deinit(core);
    for ([_][]const u8{
        "A\xcc\x81界\x1b[4munder\x1b[0m",
        "\x1b[1;1H\x1b#6wide\x1b[2;1H\x1b#3top\x1b[3;1H\x1b#4lower",
        "\x1b]66;s=2:w=2:n=1:d=2:v=1:h=2;Hi\x07\x1b[3;10Hxy",
        "one\r\ntwo\r\nthree\r\nfour\r\nfive",
        "\x1b[?1049h\x1b[48;2;10;20;30m alternate \x1b[2;2H\x1b[5 q",
        "\x1b[7mreverse\x1b[0m\x1b[38;2;10;20;30mjfj\x1b[3;12HX",
    }) |bytes| {
        vt.owner.reset(value);
        try feed(value, bytes);
        const actual = try capture(a, std.math.maxInt(u32), &.{});
        defer release(a);
        const observation = vt.owner.observation(value);
        const view = observation.semanticView(std.math.maxInt(u32));
        try render.terminal.updateObservation(core, observation, view.history_offset, &.{});
        var commands: [4096]render.terminal.Command = undefined;
        var pixels: [65536]u8 = undefined;
        var uploads: [8]render.terminal.FrameResourceUpload = undefined;
        var removals: [8]render.terminal.ResourceRef = undefined;
        const expected = try render.terminal.frame(core, &.{}, .{ .commands = &commands, .uploads = &uploads, .removals = &removals, .pixels = &pixels });
        var projected: [4096]c.hrc_command = undefined;
        const expected_commands = try native.commands(expected.commands, &projected);
        try std.testing.expectEqual(expected.commands.len, actual.info.command_count);
        try std.testing.expectEqual(expected.content_command_count, actual.info.content_command_count);
        try std.testing.expectEqual(view.history_offset, actual.info.history_offset);
        try std.testing.expectEqual(view.history_row_base, actual.info.history_row_base);
        try std.testing.expectEqual(@intFromBool(view.is_alternate_screen), actual.info.alternate_screen);
        for (expected_commands, records(c.hrc_command, actual.commands, actual.info.command_count)) |left, right| try std.testing.expectEqualDeep(left, right);
        try std.testing.expectEqual(expected.uploads.len, actual.info.upload_count);
        for (expected.uploads, records(c.hrc_upload, actual.uploads, actual.info.upload_count)) |left, right| {
            try std.testing.expectEqual(@backingInt(left.resource.resource), right.info.resource);
            try std.testing.expectEqual(@backingInt(left.resource.generation), right.info.generation);
            try std.testing.expectEqualSlices(u8, expected.pixels[left.pixel_offset..][0..left.pixel_count], right.pixels[0..right.pixel_len]);
        }
    }
}

test "capacity boundaries plus one reject before allocation while exact maxima admit" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    const reader = try vt.owner.openObservation(value);
    defer source.release(reader);
    inline for (.{
        .{ "shape_entries", c.HRC_MAX_CONFIG_ITEMS },       .{ "shape_scalars", c.HRC_MAX_CONFIG_ITEMS },
        .{ "shape_glyphs", c.HRC_MAX_CONFIG_ITEMS },        .{ "atlas_entries", c.HRC_MAX_CONFIG_ITEMS },
        .{ "max_sequence_scalars", c.HRC_MAX_SHAPED },      .{ "shaped_capacity", c.HRC_MAX_SHAPED },
        .{ "raster_bytes", c.HRC_MAX_RASTER_BYTES },        .{ "command_capacity", c.HRC_MAX_FRAME_COMMANDS },
        .{ "command_limit", c.HRC_MAX_FRAME_COMMANDS },     .{ "frame_pixel_limit", c.HRC_MAX_FRAME_PIXEL_BYTES },
        .{ "frame_buffer_limit", c.HRC_MAX_FRAME_BUFFERS },
    }) |boundary| {
        var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
        var options = config();
        options.shape_scalars = c.HRC_MAX_CONFIG_ITEMS;
        options.command_limit = c.HRC_MAX_FRAME_COMMANDS;
        @field(options, boundary[0]) = boundary[1];
        try std.testing.expectError(error.OutOfMemory, owner.create(failing.allocator(), &options, reader));
        @field(options, boundary[0]) = boundary[1] + 1;
        try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &options, reader));
        @field(options, boundary[0]) = 0;
        try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &options, reader));
    }
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var options = config();
    options.atlas_width = 4096;
    options.atlas_height = 4096;
    options.frame_pixel_limit = c.HRC_MAX_RASTER_BYTES;
    try std.testing.expectError(error.OutOfMemory, owner.create(failing.allocator(), &options, reader));
    options.atlas_height += 1;
    try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &options, reader));
    options = config();
    var fallbacks: [c.HRC_MAX_FONT_FALLBACKS]c.hrc_bytes = @splat(.{ .data = font_path.ptr, .len = font_path.len });
    options.fonts[0].fallbacks = &fallbacks;
    options.fonts[0].fallback_count = fallbacks.len;
    try std.testing.expectError(error.OutOfMemory, owner.create(failing.allocator(), &options, reader));
    options.fonts[0].fallback_count += 1;
    try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &options, reader));
}

test "pixel exhaustion retains other leases and allow truthful retry" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    var options = config();
    options.frame_pixel_limit = 65536;
    const renderer = try setup(std.testing.allocator, value, &options);
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const b = try owner.open(renderer);
    defer close(b);
    try feed(value, "A");
    const first = try capture(a, 0, &.{});
    defer release(a);
    const before = digest(first);
    var truth_storage: [8]c.hrc_residency = undefined;
    const truth = resident(first, &truth_storage);
    try feed(value, "\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1,q=2;AQIDBA==\x1b\\");
    try std.testing.expectError(error.ResourceLimit, owner.capture(b, 0, &.{}));
    try std.testing.expectError(error.NoFrame, owner.read(b));
    try std.testing.expectEqual(before, digest(try owner.read(a)));
    const retry = try capture(b, 0, truth);
    defer release(b);
    try std.testing.expectEqual(@as(u32, 1), retry.info.upload_count);
    try std.testing.expectEqual(@as(u8, c.HRC_RGBA8), retry.uploads[0].info.format);
}

test "capture bounds and unknown source pixels never mutate canonical VT geometry" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    const renderer = try setup(std.testing.allocator, value, &config());
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    try vt.owner.resize(value, c.HRC_MAX_ROWS, c.HRC_MAX_COLUMNS, 8, 16);
    const exact = try capture(a, 0, &.{});
    try std.testing.expectEqual(@as(u16, c.HRC_MAX_ROWS) * exact.info.cell_height, exact.info.surface_height);
    try owner.release(a);
    const before = vt.owner.observe(value, 0);
    try vt.owner.resize(value, c.HRC_MAX_ROWS + 1, c.HRC_MAX_COLUMNS, 8, 16);
    try std.testing.expectError(error.ResourceLimit, owner.capture(a, 0, &.{}));
    try vt.owner.resize(value, 3, c.HRC_MAX_COLUMNS + 1, 8, 16);
    try std.testing.expectError(error.ResourceLimit, owner.capture(a, 0, &.{}));
    try std.testing.expect(before.cell_width == 8 and before.cell_height == 16);
    const unknown = try vt.owner.create(std.testing.allocator, &.{ .rows = 3, .columns = 12, .history_rows = 0, .reserved = 0, .cell_width = 0, .cell_height = 0 });
    defer vt.owner.destroy(unknown);
    try feed(unknown, "\x1b_Ga=T,f=32,s=1,v=1,i=7,C=1,q=2;AQIDBA==\x1b\\");
    const image_renderer = try setup(std.testing.allocator, unknown, &config());
    defer destroy(image_renderer);
    const image_frame = try owner.open(image_renderer);
    defer close(image_frame);
    try std.testing.expectError(error.InvalidView, owner.capture(image_frame, 0, &.{}));
    const after = vt.owner.observe(unknown, 0);
    try std.testing.expect(after.cell_width == 0 and after.cell_height == 0);
}

test "seven missing images plus eight old residencies use the full fifteen-record prospective set" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    try feed(value, "A");
    for (1..8) |id| {
        var packet: [128]u8 = undefined;
        try feed(value, try std.fmt.bufPrint(&packet, "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i={d},C=1,q=2;AQIDBA==\x1b\\", .{id}));
    }
    const renderer = try setup(std.testing.allocator, value, &config());
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const b = try owner.open(renderer);
    defer close(b);
    const first = try capture(a, 0, &.{});
    defer release(a);
    try std.testing.expectEqual(@as(u32, 8), first.info.upload_count);
    const before = digest(first);
    var storage: [8]c.hrc_residency = undefined;
    const truth = resident(first, &storage);
    try feed(value, "\x1b_Gq=2,a=d,d=A\x1b\\");
    for (20..27) |id| {
        var packet: [128]u8 = undefined;
        try feed(value, try std.fmt.bufPrint(&packet, "\x1b[1;1H\x1b_Ga=T,f=32,s=1,v=1,i={d},C=1,q=2;BQYHCA==\x1b\\", .{id}));
    }
    const next = try capture(b, 0, truth);
    defer release(b);
    try std.testing.expectEqual(@as(u32, 7), next.info.upload_count);
    try std.testing.expectEqual(@as(u32, 7), next.info.removal_count);
    for (records(c.hrc_upload, next.uploads, next.info.upload_count)) |upload| {
        try std.testing.expectEqual(@as(u8, c.HRC_RGBA8), upload.info.format);
        try std.testing.expectEqualSlices(u8, &.{ 5, 6, 7, 8 }, upload.pixels[0..upload.pixel_len]);
        for (records(c.hrc_removal, next.removals, next.info.removal_count)) |removal| try std.testing.expect(removal.resource != upload.info.resource);
    }
    try std.testing.expectEqual(before, digest(try owner.read(a)));
}

test "image destination scaling uses canonical source pixels and font-derived presentation cells" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    try feed(value, "\x1b[2;2H\x1b_Ga=T,f=32,s=1,v=1,i=7,X=3,Y=5,C=1,q=2;AQIDBA==\x1b\\");
    const renderer = try setup(std.testing.allocator, value, &config());
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const view = try capture(a, 0, &.{});
    defer release(a);
    const cell = owner.cellSize(renderer);
    const observation = vt.owner.observation(value);
    const graphics = observation.images(0);
    const placement = graphics.placement(0).?;
    var seen = false;
    for (records(c.hrc_command, view.commands, view.info.command_count)) |command| {
        if (command.tag != c.HRC_RGBA) continue;
        seen = true;
        const x = @as(u64, placement.col) * 8 + placement.cell_x;
        const y = @as(u64, placement.row) * 16 + placement.cell_y;
        const left = x * cell.width / 8;
        const top = y * cell.height / 16;
        const right = ((x + placement.pixel_width) * cell.width + 7) / 8;
        const bottom = ((y + placement.pixel_height) * cell.height + 15) / 16;
        try std.testing.expectEqual(@as(i32, @intCast(left)), command.destination_x);
        try std.testing.expectEqual(@as(i32, @intCast(top)), command.destination_y);
        try std.testing.expectEqual(right - left, command.destination_width);
        try std.testing.expectEqual(bottom - top, command.destination_height);
    }
    try std.testing.expect(seen);
    const unchanged = vt.owner.observe(value, 0);
    try std.testing.expect(unchanged.cell_width == 8 and unchanged.cell_height == 16);
}

test "explicit incompatible style metrics fail construction without source mutation" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    const regular = try render.text.FontSet.init(std.testing.allocator, .{ .primary = font_path, .size = .{ .pixels = 18 } });
    defer regular.deinit();
    const other_path = @import("test_fonts").normal_ligature_font;
    const other = try render.text.FontSet.init(std.testing.allocator, .{ .primary = other_path, .size = .{ .pixels = 18 } });
    defer other.deinit();
    try std.testing.expect(!std.meta.eql(regular.metrics(), other.metrics()));
    var options = config();
    options.fonts[1] = .{ .kind = c.HRC_FONT_PATH, .reserved = @splat(0), .primary = .{ .data = other_path.ptr, .len = other_path.len }, .fallbacks = null, .fallback_count = 0 };
    const before = vt.owner.observe(value, 0);
    try std.testing.expectError(error.InvalidFontFaces, setup(std.testing.allocator, value, &options));
    try std.testing.expectEqualDeep(before, vt.owner.observe(value, 0));
}

test "font byte and aggregate bounds admit exact maxima before allocation and reject excess" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    const reader = try vt.owner.openObservation(value);
    defer source.release(reader);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    const memory = try std.testing.allocator.alloc(u8, c.HRC_MAX_FONT_BYTES);
    defer std.testing.allocator.free(memory);
    @memset(memory, 0);
    var options = config();
    options.fonts[0].kind = c.HRC_FONT_MEMORY;
    options.fonts[0].primary = .{ .data = memory.ptr, .len = memory.len };
    const fallbacks = [_]c.hrc_bytes{ .{ .data = memory.ptr, .len = memory.len }, .{ .data = memory.ptr, .len = 1 } };
    options.fonts[0].fallbacks = &fallbacks;
    options.fonts[0].fallback_count = 1;
    try std.testing.expectError(error.OutOfMemory, owner.create(failing.allocator(), &options, reader));
    options.fonts[0].fallback_count = 2;
    try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &options, reader));
    options.fonts[0].primary.len += 1;
    try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &options, reader));
    var path: [c.HRC_MAX_FONT_PATH_BYTES]u8 = @splat('x');
    options = config();
    options.fonts[0].primary = .{ .data = &path, .len = path.len };
    try std.testing.expectError(error.OutOfMemory, owner.create(failing.allocator(), &options, reader));
    options.fonts[0].primary.len += 1;
    try std.testing.expectError(error.ResourceLimit, owner.create(failing.allocator(), &options, reader));
    options.fonts[0].primary.len = path.len;
    path[path.len - 1] = 0;
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &options, reader));
    options = config();
    options.fonts[0].kind = 99;
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &options, reader));
    options = config();
    options.fonts[0].reserved[0] = 1;
    try std.testing.expectError(error.InvalidArgument, owner.create(failing.allocator(), &options, reader));
}

test "configured one-command hard limit rejects publication and permits smaller truthful retry" {
    const value = try terminal();
    defer vt.owner.destroy(value);
    var options = config();
    options.command_capacity = 1;
    options.command_limit = 1;
    const renderer = try setup(std.testing.allocator, value, &options);
    defer destroy(renderer);
    const a = try owner.open(renderer);
    defer close(a);
    const before = vt.owner.observe(value, 0);
    try std.testing.expectError(error.CommandLimit, owner.capture(a, 0, &.{}));
    try std.testing.expectError(error.NoFrame, owner.read(a));
    try std.testing.expectEqualDeep(before, vt.owner.observe(value, 0));
    // One full-surface background now fits exactly, without cursor commands.
    try feed(value, "\x1b[?25l");
    const retried = try capture(a, 0, &.{});
    defer release(a);
    try std.testing.expectEqual(@as(u32, 1), retried.info.command_count);
}
