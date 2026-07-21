const std = @import("std");
const window = @import("window.zig");

pub fn main(init: std.process.Init) !void {
    const arguments = try init.minimal.args.toSlice(init.gpa);
    defer init.gpa.free(arguments);
    if (arguments.len < 2) return error.MissingFontPath;
    try window.run(init.gpa, init.io, arguments[1..]);
}
