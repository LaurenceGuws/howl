//! Starts, joins, and retires the Window and Render lifetime owners.

const std = @import("std");
const renderer = @import("renderer.zig");
const shared = @import("shared.zig");
const window = @import("window.zig");

pub fn main() !void {
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    var boundary = try shared.Boundary.init(threaded.io());
    defer boundary.deinit();

    const window_thread = try std.Thread.spawn(.{}, window.run, .{&boundary});
    const render_thread = std.Thread.spawn(.{}, renderer.run, .{&boundary}) catch |failure| {
        boundary.requestStop(.render);
        window_thread.join();
        return failure;
    };
    render_thread.join();
    boundary.requestStop(null);
    window_thread.join();

    const stopped = boundary.stopped();
    if (!stopped.window or !stopped.render) return error.OwnerDidNotStop;
    if (boundary.failure) |failure| {
        std.debug.print("Howl stopped after {s} runtime failure\n", .{@tagName(failure)});
        return error.HostFailure;
    }
    std.debug.print("Howl color ring retired cleanly\n", .{});
}
