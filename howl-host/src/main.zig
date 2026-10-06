//! Starts, joins, and retires the Window, Input, and Render lifetime owners.

const std = @import("std");
const render = @import("howl_instance").render;
const text = render.text;
const input_owner = @import("input_owner.zig");
const layout = @import("layout.zig");
const local_terminal = @import("local_terminal");
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

    var positional_end = argv.len;
    var scan_index: usize = 1;
    while (scan_index < argv.len) : (scan_index += 1) {
        if (std.mem.eql(u8, std.mem.span(argv[scan_index]), "--fallback")) {
            positional_end = scan_index;
            break;
        }
    }
    if (positional_end != 2) {
        printUsage();
        return error.InvalidArguments;
    }

    var fallback_storage: [text.max_fallbacks][]const u8 = undefined;
    var fallback_count: usize = 0;
    var option_index = positional_end;
    while (option_index < argv.len) {
        if (!std.mem.eql(u8, std.mem.span(argv[option_index]), "--fallback") or
            option_index + 1 >= argv.len or fallback_count == fallback_storage.len)
        {
            printUsage();
            return error.InvalidArguments;
        }
        const path = std.mem.span(argv[option_index + 1]);
        if (path.len == 0) {
            printUsage();
            return error.InvalidArguments;
        }
        fallback_storage[fallback_count] = path;
        fallback_count += 1;
        option_index += 2;
    }

    const shell = init.environ_map.get("SHELL") orelse "/bin/sh";
    const font = renderer.FontPaths{
        .primary = std.mem.span(argv[1]),
        .fallbacks = fallback_storage[0..fallback_count],
    };
    var mux = layout.Mux.init();
    std.debug.assert(mux.tabCount() == 1 and mux.paneCount() == 1);
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    var boundary = try shared.Boundary.init(threaded.io());
    defer boundary.deinit();
    var local_owner = try local_terminal.Owner.init(
        std.heap.c_allocator,
        threaded.io(),
        init.minimal.environ,
        .{
            .shell = shell,
            .rows = 24,
            .columns = 80,
        },
    );
    defer local_owner.deinit();

    const window_thread = try std.Thread.spawn(.{}, window.run, .{&boundary});
    const input_thread = std.Thread.spawn(.{}, input_owner.run, .{
        &boundary,
        &local_owner,
    }) catch |failure| {
        boundary.requestStop(.input);
        window_thread.join();
        return failure;
    };
    const render_thread = std.Thread.spawn(.{}, renderer.run, .{
        &boundary,
        std.heap.c_allocator,
        &local_owner,
        font,
        mux,
    }) catch |failure| {
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

fn printUsage() void {
    std.debug.print(
        "usage: howl-host FONT [--fallback FONT ...]\n",
        .{},
    );
}
