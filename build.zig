const std = @import("std");

pub fn build(b: *std.Build) void {
    const check = b.step("check", "Check active Howl projects");
    inline for (.{
        "howl-vt",
        "howl-headless",
        "howl-text",
        "howl-host",
    }) |package| {
        const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "check" });
        run.setCwd(b.path(package));
        check.dependOn(&run.step);
    }
    b.default_step = check;
}
