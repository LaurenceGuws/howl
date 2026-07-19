const std = @import("std");
const benchmark = @import("terminal_benchmark.zig");

pub fn main(init: std.process.Init) !void {
    return benchmark.main(init);
}
