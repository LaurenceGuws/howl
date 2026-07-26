//! Starts, joins, and retires the Window and Render lifetime owners.

const std = @import("std");
const renderer = @import("renderer.zig");
const shared = @import("shared.zig");
const window = @import("window.zig");

const MainError = std.Thread.SpawnError || error{
    Signal,
    OwnerDidNotStop,
    HostFailure,
    InvalidArguments,
};

/// Owns process-root construction, joins both runtime owners, and reports the
/// first construction or owner failure after reverse cleanup.
pub fn main(init: std.process.Init) MainError!void {
    var iterator = init.minimal.args.iterate();
    const executable_name = iterator.next() orelse return error.InvalidArguments;
    if (executable_name.len == 0) return error.InvalidArguments;
    if (!std.mem.eql(u8, iterator.next() orelse return error.InvalidArguments, "--font"))
        return error.InvalidArguments;
    const font_path = iterator.next() orelse return error.InvalidArguments;
    if (font_path.len == 0 or iterator.next() != null) return error.InvalidArguments;
    var boundary = try shared.Boundary.init(init.io);
    defer boundary.deinit();

    const window_thread = try std.Thread.spawn(.{}, window.run, .{&boundary});
    const render_thread = std.Thread.spawn(.{}, renderer.run, .{ &boundary, init.gpa, font_path }) catch |failure| {
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
    std.debug.print("Howl Vulkan surface retired cleanly\n", .{});
}
