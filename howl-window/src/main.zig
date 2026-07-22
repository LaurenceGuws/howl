const std = @import("std");
const probe = @import("howl_probe");
const window = @import("window.zig");

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(arguments);
    if (arguments.len < 2) return error.MissingFontPath;
    try probe.start(init.io, "howl-window-probe.jsonl");
    var window_failure: ?window.Error = null;
    window.run(init.gpa, init.io, arguments[1..]) catch |failure| {
        window_failure = failure;
    };
    const summary = probe.stop() catch |failure| {
        if (window_failure != null)
            @panic("window and development probe failed distinctly");
        return failure;
    };
    if (probe.enabled) {
        var buffer: [256]u8 = undefined;
        var writer = std.Io.File.stderr().writer(init.io, &buffer);
        try writer.interface.print(
            "probe events={d} dropped={d} high_water={d}/{d} records={d} samples={d} output=howl-window-probe.jsonl\n",
            .{
                summary.accepted,
                summary.dropped,
                summary.high_water,
                probe.queue_capacity,
                summary.records,
                summary.samples,
            },
        );
        try writer.interface.flush();
    }
    if (window_failure) |failure| return failure;
}
