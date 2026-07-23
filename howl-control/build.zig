const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const vt = b.dependency("howl_vt", .{ .target = target, .optimize = optimize });
    const pty = b.dependency("howl_pty", .{ .target = target, .optimize = optimize });
    const module = b.addModule("howl_control", .{
        .root_source_file = b.path("src/howl_control.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addImport("howl_vt", vt.module("howl_vt"));
    module.addImport("howl_pty", pty.module("howl_pty"));

    const api = b.addTest(.{
        .name = "howl-control-api",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const tests_module = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests_module.addImport("howl_control", module);
    const tests = b.addTest(.{
        .name = "howl-control",
        .root_module = tests_module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile embedded control, client, and live PTY proofs");
    check.dependOn(&api.step);
    check.dependOn(&tests.step);
    const run_api = b.addRunArtifact(api);
    const run_tests = b.addRunArtifact(tests);
    run_api.addPassthruArgs();
    run_tests.addPassthruArgs();
    const test_step = b.step("test", "Run embedded control, client, and live PTY proofs");
    test_step.dependOn(&run_api.step);
    test_step.dependOn(&run_tests.step);
    b.default_step = check;
}
