const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const vt = b.dependency("howl_vt", .{ .target = target, .optimize = optimize });
    const module = b.addModule("howl_frame", .{
        .root_source_file = b.path("src/howl_frame.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_vt", vt.module("howl_vt"));
    const tests = b.addTest(.{ .name = "howl-frame", .root_module = module, .filters = b.args orelse &.{} });
    tests.use_llvm = true;
    const check = b.step("check", "Compile the immutable frame owner and proofs");
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    if (b.args != null) run_tests.has_side_effects = true;
    b.step("test", "Run the immutable frame proofs").dependOn(&run_tests.step);
    b.default_step = check;
}
