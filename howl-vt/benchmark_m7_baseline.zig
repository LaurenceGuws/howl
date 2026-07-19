pub fn main(init: @import("std").process.Init) !void {
    return @import("benchmark/m7_baseline.zig").main(init);
}
