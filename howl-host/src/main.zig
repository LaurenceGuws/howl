//! Starts, joins, and retires the Window, Input, and Render lifetime owners.

const std = @import("std");
const input_owner = @import("input_owner.zig");
const layout = @import("layout.zig");
const renderer = @import("renderer.zig");
const session_process = @import("session_process.zig");
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
    if (argv.len < 2 or argv.len > 4) {
        std.debug.print(
            "usage: howl-host FONT | ENDPOINT FONT | ENDPOINT_LEFT ENDPOINT_RIGHT FONT\n",
            .{},
        );
        return error.InvalidArguments;
    }
    var owned_session: ?session_process.SessionProcess = null;
    defer if (owned_session) |*session| session.deinit();

    const runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR");
    const shell = init.environ_map.get("SHELL") orelse "/bin/sh";
    const owned_mode = argv.len == 2;
    if (owned_mode) {
        const owned_runtime_dir = runtime_dir orelse return error.MissingRuntimeDirectory;
        owned_session = try session_process.SessionProcess.launchSibling(
            init.gpa,
            init.io,
            owned_runtime_dir,
            shell,
            null,
            null,
            init.environ_map,
            24,
            80,
            1,
        );
    }
    const endpoint: []const u8 = if (owned_session) |*session|
        session.endpoint
    else
        std.mem.span(argv[1]);
    const endpoint_right: ?[]const u8 = if (argv.len == 4)
        std.mem.span(argv[2])
    else
        null;
    const font_path = std.mem.span(argv[switch (argv.len) {
        2 => 1,
        3 => 2,
        4 => 3,
        else => unreachable,
    }]);
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

    const window_thread = try std.Thread.spawn(.{}, window.run, .{&boundary});
    const input_thread = std.Thread.spawn(.{}, input_owner.run, .{
        &boundary,
        std.heap.c_allocator,
        endpoint,
        endpoint_right,
        mux,
    }) catch |failure| {
        boundary.requestStop(.input);
        window_thread.join();
        return failure;
    };
    const render_thread = std.Thread.spawn(.{}, renderer.run, .{
        &boundary,
        std.heap.c_allocator,
        endpoint,
        endpoint_right,
        font_path,
        mux,
        runtime_dir,
        shell,
        init.environ_map,
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
