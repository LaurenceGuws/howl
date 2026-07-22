const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const frame = b.dependency("howl_frame", .{ .target = target, .optimize = optimize });
    const text = b.dependency("howl_text", .{ .target = target, .optimize = optimize });
    const module = b.addModule("howl_render", .{
        .root_source_file = b.path("src/howl_render.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addImport("howl_frame", frame.module("howl_frame"));
    module.addImport("howl_text", text.module("howl_text"));
    const paths = b.addOptions();
    paths.addOption([]const u8, "font", text.path("testdata/primary.ttf").getPath(b));
    module.addImport("render_test_paths", paths.createModule());
    const tests = b.addTest(.{ .name = "howl-render", .root_module = module, .filters = b.args orelse &.{} });
    tests.use_llvm = true;
    const check = b.step("check", "Compile shared render preparation and proofs");
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    if (b.args != null) run_tests.has_side_effects = true;
    b.step("test", "Run shared render and cache proofs").dependOn(&run_tests.step);
    b.default_step = check;
}
