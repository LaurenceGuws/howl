//! Starts, joins, and retires the Window, Input, and Render lifetime owners.

const std = @import("std");
const text = @import("howl_text");
const input_owner = @import("input_owner.zig");
const layout = @import("layout.zig");
const local_terminal = @import("local_terminal");
const remote_target = @import("remote_target.zig");
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
    const server_mode = argv.len >= 2 and std.mem.eql(u8, std.mem.span(argv[1]), "--server");

    var positional_end = argv.len;
    var scan_index: usize = 1;
    while (scan_index < argv.len) : (scan_index += 1) {
        if (std.mem.eql(u8, std.mem.span(argv[scan_index]), "--fallback")) {
            positional_end = scan_index;
            break;
        }
    }
    const positionals_valid = if (local_mode)
        positional_end == 3
    else if (server_mode)
        positional_end == 7
    else
        positional_end == 3 or positional_end == 4;
    if (!positionals_valid) {
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
    const primary_target: ?remote_target.Target = if (local_mode)
        null
    else if (server_mode)
        .{ .server = .{
            .endpoint = std.mem.span(argv[2]),
            .server_id = parseIdentity(std.mem.span(argv[3])) catch {
                printUsage();
                return error.InvalidArguments;
            },
            .session_id = parseIdentity(std.mem.span(argv[4])) catch {
                printUsage();
                return error.InvalidArguments;
            },
            .instance_id = parseIdentity(std.mem.span(argv[5])) catch {
                printUsage();
                return error.InvalidArguments;
            },
        } }
    else
        .{ .direct = std.mem.span(argv[1]) };
    const target_right: ?remote_target.Target = if (!local_mode and !server_mode and positional_end == 4)
        .{ .direct = std.mem.span(argv[2]) }
    else
        null;
    const font_index: usize = if (local_mode)
        2
    else if (server_mode)
        6
    else if (positional_end == 4)
        3
    else
        2;
    const font = renderer.FontPaths{
        .primary = std.mem.span(argv[font_index]),
        .fallbacks = fallback_storage[0..fallback_count],
    };
    var mux = layout.Mux.init();
    if (target_right != null) {
        const right_pane = try mux.splitFocused(.horizontal);
        std.debug.assert(mux.focusedPane() == right_pane);
    }
    const expected_panes: u8 = if (target_right != null) 2 else 1;
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
            primary_target.?,
            target_right,
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
            font,
            mux,
        })
    else
        std.Thread.spawn(.{}, renderer.run, .{
            &boundary,
            std.heap.c_allocator,
            primary_target.?,
            target_right,
            font,
            mux,
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

fn parseIdentity(value_text: []const u8) error{InvalidIdentity}!u64 {
    const value = std.fmt.parseInt(u64, value_text, 10) catch return error.InvalidIdentity;
    if (value == 0) return error.InvalidIdentity;
    return value;
}

fn printUsage() void {
    std.debug.print(
        "usage: howl-host --local FONT [--fallback FONT ...] | " ++
            "ENDPOINT FONT [--fallback FONT ...] | " ++
            "ENDPOINT_LEFT ENDPOINT_RIGHT FONT [--fallback FONT ...] | " ++
            "--server SERVER_ENDPOINT SERVER_ID SESSION_ID INSTANCE_ID FONT [--fallback FONT ...]\n",
        .{},
    );
}
