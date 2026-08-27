const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const session = b.dependency("howl_session", .{ .target = target, .optimize = optimize });
    const module = b.addModule("howl_cli", .{
        .root_source_file = b.path("src/howl_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_session", session.module("howl_session"));
    const tests = b.addTest(.{
        .name = "howl-cli",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const main_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    main_module.addImport("howl_cli", module);
    const executable = b.addExecutable(.{ .name = "howl", .root_module = main_module });
    const check = b.step("check", "Compile the bounded Howl operator and agent CLI");
    check.dependOn(&tests.step);
    check.dependOn(&executable.step);
    const test_step = b.step("test", "Run the bounded Howl session client proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    b.installArtifact(executable);
    b.default_step = check;
}
