//! Workspace build and repository hygiene checks.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const shape_check = b.addSystemCommand(&.{ "sh", "tools/check_module_shape.sh" });
    const host_runtime_surface = b.addSystemCommand(&.{ "bash", "tools/check_host_runtime_surface.sh" });

    const check_step = b.step("check", "Run workspace hygiene checks");
    check_step.dependOn(&shape_check.step);
    check_step.dependOn(&host_runtime_surface.step);
    b.default_step.dependOn(check_step);

    const test_step = b.step("test", "Run all workspace tests");
    test_step.dependOn(check_step);

    _ = addRepoBuild(b, test_step, "howl-vt-core", &.{ "test", "--summary", "all" });
    _ = addRepoBuild(b, test_step, "howl-session", &.{ "test", "--summary", "all" });
    _ = addRepoBuild(b, test_step, "howl-render-core", &.{ "test", "--summary", "all" });
    _ = addRepoBuild(b, test_step, "howl-term", &.{ "test", "--summary", "all" });

    const host_build = addRepoBuild(b, test_step, "howl-hosts/howl-linux-host", &.{ "--summary", "all" });
    const host_test = addRepoBuild(b, test_step, "howl-hosts/howl-linux-host", &.{ "test", "--summary", "all" });
    host_test.step.dependOn(&host_build.step);
}

fn addRepoBuild(b: *std.Build, parent: *std.Build.Step, path: []const u8, args: []const []const u8) *std.Build.Step.Run {
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.addArgs(args);
    run.setCwd(b.path(path));
    parent.dependOn(&run.step);
    return run;
}
