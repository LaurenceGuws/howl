const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const instance = b.dependency("howl_instance", .{ .target = target, .optimize = optimize });
    const client = b.dependency("howl_client", .{ .target = target, .optimize = optimize });
    const server_client = b.dependency("server_client", .{ .target = target, .optimize = optimize });
    const server = b.dependency("server", .{ .target = target, .optimize = optimize });

    const module = b.addModule("howl_cli", .{
        .root_source_file = b.path("src/howl_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_instance", instance.module("howl_instance"));
    module.addImport("howl_client", client.module("howl_client"));

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root.addImport("howl_cli", module);
    root.addImport("howl_client", client.module("howl_client"));
    root.addImport("howl_instance", instance.module("howl_instance"));
    root.addImport("server_client", server_client.module("server_client"));
    root.addImport("server_runtime", server.module("server_runtime"));
    const executable = b.addExecutable(.{ .name = "howl", .root_module = root });
    b.installArtifact(executable);

    const tests = b.addTest(.{
        .name = "howl-cli",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });

    const runtime_test_root = b.createModule(.{
        .root_source_file = b.path("test/server_runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime_test_root.addImport("server_runtime", server.module("server_runtime"));
    runtime_test_root.addImport("server_client", server_client.module("server_client"));
    runtime_test_root.addImport("howl_client", client.module("howl_client"));
    const runtime_tests = b.addTest(.{
        .name = "howl-cli-server-runtime",
        .root_module = runtime_test_root,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the native Howl CLI");
    check.dependOn(&executable.step);
    check.dependOn(&tests.step);
    check.dependOn(&runtime_tests.step);
    const test_step = b.step("test", "Run native Howl CLI proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(runtime_tests).step);
    b.default_step = check;
}
