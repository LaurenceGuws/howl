//! Starts, joins, and retires the Window, Input, and Render lifetime owners.

const std = @import("std");
const input_owner = @import("input_owner.zig");
const layout = @import("layout.zig");
const renderer = @import("renderer.zig");
const shared = @import("shared.zig");
const window = @import("window.zig");

const MainError = std.Thread.SpawnError || error{
    Signal,
    OwnerDidNotStop,
    HostFailure,
};

/// Owns process-root construction, joins all runtime owners, and reports the
/// first construction or owner failure after reverse cleanup.
pub fn main(init: std.process.Init) !void {
    const argv = init.minimal.args.vector;
    if (argv.len != 3) {
        std.debug.print("usage: howl-host ENDPOINT FONT\n", .{});
        return error.InvalidArguments;
    }
    const endpoint = std.mem.span(argv[1]);
    const font_path = std.mem.span(argv[2]);
    var mux = layout.Mux.init();
    std.debug.assert(mux.tabCount() == 1 and mux.paneCount() == 1);
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    var boundary = try shared.Boundary.init(threaded.io());
    defer boundary.deinit();

    const window_thread = try std.Thread.spawn(.{}, window.run, .{&boundary});
    const input_thread = std.Thread.spawn(.{}, input_owner.run, .{ &boundary, std.heap.c_allocator, endpoint }) catch |failure| {
        boundary.requestStop(.input);
        window_thread.join();
        return failure;
    };
    const render_thread = std.Thread.spawn(.{}, renderer.run, .{ &boundary, std.heap.c_allocator, endpoint, font_path }) catch |failure| {
        boundary.requestStop(.render);
        input_thread.join();
        window_thread.join();
        return failure;
    };
    render_thread.join();
    boundary.requestStop(null);
    input_thread.join();
    window_thread.join();

    const stopped = boundary.stopped();
    if (!stopped.window or !stopped.render or !stopped.input) return error.OwnerDidNotStop;
    if (boundary.failure) |failure| {
        std.debug.print("Howl stopped after {s} runtime failure\n", .{@tagName(failure)});
        return error.HostFailure;
    }
    std.debug.print("Howl terminal frame retired cleanly\n", .{});
}
