//! Real foreign frame/lifetime proof through public C construction and operations.
const std = @import("std");
const instance = @import("howl_instance");
const native = @import("howl_instance_native");
const c = native.c;
const fonts = @import("test_fonts");
extern fn howl_native_frame_peer(?*c.hi_instance, *const fn (*Context) callconv(.c) c_int, *Context) c_int;
extern fn howl_native_large_frame_peer(?*c.hi_instance, usize) c_int;
const Context = struct { owner: *c.hi_instance, io: std.Io, before: u64 };
fn advance(context: *Context) callconv(.c) c_int {
    if (c.hi_send_text(context.owner, "next\n", 5) != c.HI_OK) return 1;
    for (0..2000) |_| {
        var turn: c.hi_service = undefined;
        if (c.hi_service_turn(context.owner, 1, 1, @intCast(std.Io.Clock.awake.now(context.io).toNanoseconds()), &turn) != c.HI_OK) return 2;
        if (turn.terminal_revision > context.before) return if (c.hi_publish_frame(context.owner, 0) == c.HI_OK) 0 else 3;
        std.Io.sleep(context.io, .fromMilliseconds(1), .awake) catch return 4;
    }
    return 5;
}
fn createPresented(command_capacity: usize, command: []const u8, rows: u16, columns: u16, history: u16) !*c.hi_instance {
    var config = std.mem.zeroes(c.hi_presentation_config);
    config.fonts[0].kind = c.HI_FONT_PATH;
    config.fonts[0].primary = .{ .data = fonts.primary_font.ptr, .len = fonts.primary_font.len };
    config.pixel_size = 18;
    config.max_sequence_scalars = 16;
    config.shape_entries = 256;
    config.shape_scalars = 512;
    config.shape_glyphs = 512;
    config.shaped_capacity = 1024;
    config.raster_bytes = 64 * 1024;
    var presentation: ?*c.hi_presentation = null;
    try std.testing.expectEqual(@as(u32, c.HI_OK), c.hi_presentation_create(c.HI_ABI_VERSION, &config, &presentation));
    defer std.testing.expectEqual(@as(u32, c.HI_OK), c.hi_presentation_release(&presentation)) catch {
        // zig-audit: acknowledge panic
        // reason: A failed release in proof cleanup is an invariant violation that must fail this test.
        @panic("presentation cleanup failed");
    };
    var renderer = std.mem.zeroes(c.hi_presented_config);
    renderer.stroke_points = .{ 0.001, 1, 1.5, 2 };
    renderer.dpi_x_numerator = 96;
    renderer.dpi_x_denominator = 1;
    renderer.dpi_y_numerator = 96;
    renderer.dpi_y_denominator = 1;
    renderer.atlas_width = 128;
    renderer.atlas_height = 128;
    renderer.atlas_gap = 1;
    renderer.atlas_entries = 256;
    renderer.command_capacity = command_capacity;
    renderer.command_limit = command_capacity;
    const env = [_]c.hi_bytes{.{ .data = "PATH=/usr/bin:/bin", .len = "PATH=/usr/bin:/bin".len }};
    const launch = c.hi_launch{
        .shell = .{ .data = "/bin/sh", .len = "/bin/sh".len },
        .command = .{ .data = command.ptr, .len = command.len },
        .cwd = .{ .data = null, .len = 0 },
        .environment = &env,
        .environment_count = env.len,
        .rows = rows,
        .columns = columns,
        .history_rows = history,
        .reserved = 0,
        .cell_width = 0,
        .cell_height = 0,
    };
    var value: ?*c.hi_instance = null;
    try std.testing.expectEqual(@as(u32, c.HI_OK), c.hi_create_presented(c.HI_ABI_VERSION, &launch, presentation, &renderer, &value));
    return value.?;
}
fn destroy(value: *?*c.hi_instance) void {
    std.testing.expectEqual(@as(u32, c.HI_OK), c.hi_destroy(value)) catch {
        // zig-audit: acknowledge panic
        // reason: Foreign proof cleanup must report a leaked live endpoint or failed canonical destruction.
        @panic("instance cleanup failed");
    };
}
fn awaitCell(value: *c.hi_instance, io: std.Io, row: u16, column: u16, expected: u32, turns: usize) !u64 {
    for (0..turns) |_| {
        var turn: c.hi_service = undefined;
        try std.testing.expectEqual(@as(u32, c.HI_OK), c.hi_service_turn(value, 1, 1, @intCast(std.Io.Clock.awake.now(io).toNanoseconds()), &turn));
        var cell: c.hvt_cell = undefined;
        try std.testing.expectEqual(@as(u32, c.HI_OK), c.hi_copy_cell(value, 0, row, column, &cell));
        if (cell.scalar_count != 0 and cell.scalars[0] == expected) return turn.terminal_revision;
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    }
    return error.Timeout;
}
test "foreign frame lease is immutable, pins teardown and resets replacement residency" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{ .environ = std.testing.environ });
    defer threaded.deinit();
    const io = threaded.io();
    var owner: ?*c.hi_instance = try createPresented(256, "stty -echo; printf FRESH; read line; printf NEW; read line", 2, 16, 8);
    defer destroy(&owner);
    const before = try awaitCell(owner.?, io, 0, 0, 'F', 2000);
    var context = Context{ .owner = owner.?, .io = io, .before = before };
    try std.testing.expectEqual(@as(c_int, 0), howl_native_frame_peer(owner, &advance, &context));
    var copied: c.hvt_interaction = undefined;
    try std.testing.expectEqual(@as(u32, c.HI_OK), c.hi_interaction(owner, &copied));
    try std.testing.expect(copied.terminal_revision > before);
    // An open endpoint pins the C owner even between leases.
    var endpoint: ?*c.hi_frame_stream = null;
    try std.testing.expectEqual(@as(u32, c.HI_OK), c.hi_frame_open(c.HI_ABI_VERSION, owner, &endpoint));
    defer c.hi_frame_close(&endpoint);
    const saved = owner;
    try std.testing.expectEqual(@as(u32, c.HI_BUSY), c.hi_destroy(&owner));
    try std.testing.expect(owner == saved);
    c.hi_frame_close(&endpoint);
    try std.testing.expect(endpoint == null);
}

test "foreign ABI copies a real frame above the maintained host command envelope" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{ .environ = std.testing.environ });
    defer threaded.deinit();
    const io = threaded.io();
    var owner: ?*c.hi_instance = try createPresented(131072, "stty -echo; printf '%115200s' '' | tr ' ' X; read line", 225, 512, 0);
    defer destroy(&owner);
    // zig-audit: acknowledge discard
    // reason: The copied final cell establishes complete output; no later assertion needs its service revision.
    _ = try awaitCell(owner.?, io, 224, 511, 'X', 5000);
    try std.testing.expectEqual(@as(c_int, 0), howl_native_large_frame_peer(owner, instance.render.limits.maximum_frame_commands));
}

test "Instance native signal tags admit exactly the five canonical meanings" {
    for (0..256) |tag| {
        const expected: ?instance.Signal = switch (tag) {
            1 => .hangup,
            2 => .interrupt,
            3 => .resize_notify,
            9 => .kill,
            15 => .terminate,
            else => null,
        };
        try std.testing.expectEqual(expected, native.signalFromTag(@intCast(tag)));
    }
}
