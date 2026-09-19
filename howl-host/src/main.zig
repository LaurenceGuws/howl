//! Starts, joins, and retires the Window, Input, and Render lifetime owners.

const std = @import("std");
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
    const local_mode = argv.len >= 2 and std.mem.eql(u8, std.mem.span(argv[1]), "--local");
    if ((local_mode and argv.len != 3) or
        (!local_mode and (argv.len < 3 or argv.len > 4)))
    {
        std.debug.print(
            "usage: howl-host --local FONT | ENDPOINT FONT | ENDPOINT_LEFT ENDPOINT_RIGHT FONT\n",
            .{},
        );
        return error.InvalidArguments;
    }

    const runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR");
    const shell = init.environ_map.get("SHELL") orelse "/bin/sh";
    const endpoint = if (local_mode) "" else std.mem.span(argv[1]);
    const endpoint_right: ?[]const u8 = if (!local_mode and argv.len == 4)
        std.mem.span(argv[2])
    else
        null;
    const font_path = if (local_mode)
        std.mem.span(argv[2])
    else
        std.mem.span(argv[
            switch (argv.len) {
                3 => 2,
                4 => 3,
                else => unreachable,
            }
        ]);
    var mux = layout.Mux.init();
    if (endpoint_right != null) {
        const right_pane = try mux.splitFocused(.horizontal);
        std.debug.assert(mux.focusedPane() == right_pane);
    }
    const expected_panes: u8 = if (endpoint_right != null) 2 else 1;
    std.debug.assert(mux.tabCount() == 1 and mux.paneCount() == expected_panes);
    var threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    var boundary = try shared.Boundary.init(threaded.io());
    defer boundary.deinit();
    var local_owner: local_terminal.Owner = undefined;
    var local_owner_initialized = false;
    if (local_mode) {
        local_owner = try local_terminal.Owner.init(
            std.heap.c_allocator,
            threaded.io(),
            init.minimal.environ,
            .{
                .shell = shell,
                .rows = 24,
                .columns = 80,
            },
        );
        local_owner_initialized = true;
    }
    defer if (local_owner_initialized) local_owner.deinit();

    const window_thread = try std.Thread.spawn(.{}, window.run, .{&boundary});
    const input_thread = (if (local_mode)
        std.Thread.spawn(.{}, input_owner.runLocal, .{
            &boundary,
            &local_owner,
            mux,
        })
    else
        std.Thread.spawn(.{}, input_owner.run, .{
            &boundary,
            std.heap.c_allocator,
            endpoint,
            endpoint_right,
            mux,
        })) catch |failure| {
        boundary.requestStop(.input);
        window_thread.join();
        return failure;
    };
    const render_thread = (if (local_mode)
        std.Thread.spawn(.{}, renderer.runLocal, .{
            &boundary,
            std.heap.c_allocator,
            &local_owner,
            font_path,
            mux,
        })
    else
        std.Thread.spawn(.{}, renderer.run, .{
            &boundary,
            std.heap.c_allocator,
            endpoint,
            endpoint_right,
            font_path,
            mux,
            runtime_dir,
            shell,
            init.environ_map,
        })) catch |failure| {
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
