//! Starts, joins, and retires Window, Renderer, and terminal runtime owners.

const std = @import("std");
const renderer = @import("renderer.zig");
const shared = @import("shared.zig");
const terminal_runtime = @import("terminal_runtime");
const window = @import("window.zig");
const dev_config = @import("dev_config");

const MainError = std.Thread.SpawnError || dev_config.LoadError || error{
    ArithmeticOverflow,
    Signal,
    OwnerDidNotStop,
    HostFailure,
    InvalidArguments,
};

/// Owns process-root construction, joins all three runtime owners, and reports the
/// first construction or owner failure after reverse cleanup.
pub fn main(init: std.process.Init) MainError!void {
    var iterator = init.minimal.args.iterate();
    var args: [12][]const u8 = undefined;
    var arg_count: usize = 0;
    while (iterator.next()) |argument| {
        if (arg_count == args.len) return error.InvalidArguments;
        args[arg_count] = argument;
        arg_count += 1;
    }
    const parsed = try dev_config.parseArguments(args[0..arg_count]);
    try dev_config.validateFile(init.io, init.gpa, parsed.config_path);
    var boundary = try shared.Boundary.init(init.io);
    defer boundary.deinit();
    var terminals = try terminal_runtime.initBoundary(init.io, init.gpa);
    defer terminals.deinit();

    const window_thread = try std.Thread.spawn(.{}, window.run, .{&boundary});
    const terminal_thread = std.Thread.spawn(
        .{},
        terminal_runtime.run,
        .{ &terminals, init.gpa, parsed.font_path, "/bin/sh", parsed.command },
    ) catch |failure| {
        boundary.requestStop(.render);
        window_thread.join();
        return failure;
    };
    const render_thread = std.Thread.spawn(.{}, renderer.run, .{
        &boundary,
        &terminals,
        init.gpa,
        parsed.font_path,
    }) catch |failure| {
        boundary.requestStop(.render);
        terminals.shutdown();
        window_thread.join();
        terminal_thread.join();
        return failure;
    };
    render_thread.join();
    terminals.shutdown();
    boundary.requestStop(null);
    window_thread.join();
    terminal_thread.join();

    const stopped = boundary.stopped();
    if (!stopped.window or !stopped.render) return error.OwnerDidNotStop;
    const terminal_status = terminals.status();
    if (!terminal_status.stopped or terminal_status.failed) return error.HostFailure;
    if (boundary.failure) |failure| {
        std.debug.print("Howl stopped after {s} runtime failure\n", .{@tagName(failure)});
        return error.HostFailure;
    }
}
