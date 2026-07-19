//! Runs one native Howl host window until compositor or operator close.

const std = @import("std");
const cli = @import("cli.zig");
const host = @import("howl_host.zig");

const Error = host.WindowError || cli.Error;

pub fn main(init: std.process.Init) Error!void {
    const arguments = try init.minimal.args.toSlice(init.arena.allocator());
    const font_path = try cli.fontPath(arguments);
    const window = try host.Window.open(
        init.gpa,
        init.io,
        .horizontal,
        .{ .width = 800, .height = 480 },
        font_path,
    );
    var run_failure: ?host.WindowError = null;
    window.run() catch |failure| {
        run_failure = failure;
    };
    try window.deinit();
    if (run_failure) |failure| return failure;
}
