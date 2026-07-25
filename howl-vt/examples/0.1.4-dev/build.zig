const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const howl_vt = b.dependency("howl_vt", .{
        .target = target,
        .optimize = optimize,
    }).module("howl_vt");

    const runtime_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_module.addImport("howl_vt", howl_vt);
    const runtime = b.addExecutable(.{
        .name = "howl-vt-0.1.4-dev",
        .root_module = runtime_module,
        .use_llvm = false,
        .use_lld = false,
    });

    const check = b.step("check", "Compile the versioned VT runtime and contract tests");
    check.dependOn(&runtime.step);

    const tests_module = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests_module.addImport("howl_vt", howl_vt);
    const tests = b.addTest(.{
        .name = "howl-vt-0.1.4-dev-test",
        .root_module = tests_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&tests.step);

    const run_tests = b.addRunArtifact(tests);
    b.step("test", "Run the versioned VT embedding contract").dependOn(&run_tests.step);

    const run_runtime = b.addRunArtifact(runtime);
    b.step("run", "Run the versioned VT runtime").dependOn(&run_runtime.step);
    b.default_step = check;
}
