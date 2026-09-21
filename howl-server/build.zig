const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const session = b.dependency("howl_session", .{ .target = target, .optimize = optimize });

    const module = b.addModule("howl_server", .{
        .root_source_file = b.path("src/howl_server.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_session", session.module("howl_session"));
    module.addImport("howl_session_endpoint", session.module("howl_session_endpoint"));

    const tests = b.addTest(.{
        .name = "howl-server",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the bounded Howl Session collection owner");
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run Howl server collection proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    b.default_step = check;
}
