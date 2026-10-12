//! Real foreign frame/lifetime proof through public package interfaces.
const std = @import("std");
const instance = @import("howl_instance");
const native = @import("howl_instance_native");
const frames = @import("howl_instance_frames_native");
const fonts = @import("test_fonts");
extern fn howl_native_frame_peer(?*native.c.hi_instance, *const fn (*Context) callconv(.c) c_int, *Context) c_int;
extern fn howl_native_large_frame_peer(?*native.c.hi_instance, usize) c_int;
const Context = struct { owner: *instance.Instance, io: std.Io, before: u64 };
fn advance(context: *Context) callconv(.c) c_int {
    instance.input(context.owner, .{ .bytes = "next\n" }) catch return 1;
    for (0..2000) |_| {
        // zig-audit: acknowledge discard
        // reason: The proof observes canonical sequence directly; the turn summary is not the acceptance condition.
        _ = instance.service(context.owner, true, true, @intCast(std.Io.Clock.awake.now(context.io).toNanoseconds())) catch return 2;
        if (instance.terminal(context.owner).semanticSequence() > context.before) {
            instance.publishRender(context.owner) catch return 3;
            return 0;
        }
        std.Io.sleep(context.io, .fromMilliseconds(1), .awake) catch return 4;
    }
    return 5;
}
fn presentationConfig(command_capacity: usize) instance.PresentationConfig {
    return .{
        .text = .{ .private = .{ .regular = .{ .path = .{ .primary = fonts.primary_font, .size = .{ .pixels = 18 } } } } },
        .box_drawing = .{ .dpi_x = .{ .numerator = 96, .denominator = 1 }, .dpi_y = .{ .numerator = 96, .denominator = 1 } },
        .shape_cache = .{ .entry_capacity = 256, .scalar_capacity = 512, .glyph_capacity = 512, .max_sequence_scalars = 16 },
        .atlas = .{ .width = 128, .height = 128, .entry_capacity = 256 },
        .shaped_capacity = 1024,
        .raster_bytes = 64 * 1024,
        .command_capacity = command_capacity,
        .command_limit = command_capacity,
    };
}
test "foreign frame lease is immutable, pins teardown and resets replacement residency" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{ .environ = std.testing.environ });
    defer threaded.deinit();
    const io = threaded.io();
    const owner = try instance.initPresented(std.testing.allocator, std.testing.environ, .{ .shell = "/bin/sh", .command = "stty -echo; printf FRESH; read line; printf NEW; read line", .rows = 2, .columns = 16, .history_rows = 8 }, presentationConfig(256));
    defer instance.deinit(owner);
    for (0..2000) |_| {
        // zig-audit: acknowledge discard
        // reason: The proof waits for copied canonical output, not the service summary.
        _ = try instance.service(owner, true, true, @intCast(std.Io.Clock.awake.now(io).toNanoseconds()));
        if (instance.terminal(owner).semanticView(0).cellAt(0, 0) == 'F') break;
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    } else return error.Timeout;
    var context = Context{ .owner = owner, .io = io, .before = instance.terminal(owner).semanticSequence() };
    // zig-audit: acknowledge ptr_cast
    // reason: The artifact selects this exact local specialization; the peer receives its opaque constructor-owned handle, never its layout.
    const raw: *native.c.hi_instance = @ptrCast(owner);
    try std.testing.expectEqual(@as(c_int, 0), howl_native_frame_peer(raw, &advance, &context));
    try std.testing.expect(instance.terminal(owner).semanticSequence() > context.before);
    // Closing the last endpoint restores checked teardown eligibility without changing canonical state.
    const endpoint = try frames.open(std.testing.allocator, owner);
    try std.testing.expectError(error.PublicationBorrowed, instance.tryDeinit(owner));
    frames.close(endpoint);
}

test "foreign ABI copies a real frame above the maintained host command envelope" {
    var threaded = std.Io.Threaded.init(std.testing.allocator, .{ .environ = std.testing.environ });
    defer threaded.deinit();
    const io = threaded.io();
    const owner = try instance.initPresented(std.testing.allocator, std.testing.environ, .{
        .shell = "/bin/sh",
        .command = "stty -echo; printf '%115200s' '' | tr ' ' X; read line",
        .rows = 225,
        .columns = 512,
        .history_rows = 0,
    }, presentationConfig(131072));
    defer instance.deinit(owner);
    for (0..5000) |_| {
        // zig-audit: acknowledge discard
        // reason: Complete canonical output, rather than a turn summary, establishes this boundary fixture.
        _ = try instance.service(owner, true, true, @intCast(std.Io.Clock.awake.now(io).toNanoseconds()));
        if (instance.terminal(owner).semanticView(0).cellAt(224, 511) == 'X') break;
        try std.Io.sleep(io, .fromMilliseconds(1), .awake);
    } else return error.Timeout;
    // zig-audit: acknowledge ptr_cast
    // reason: The C peer receives the exact local native artifact's matching opaque owner, never a terminal layout.
    const raw: *native.c.hi_instance = @ptrCast(owner);
    try std.testing.expectEqual(@as(c_int, 0), howl_native_large_frame_peer(raw, instance.render.limits.maximum_frame_commands));
}
