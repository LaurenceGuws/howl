const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const session = b.dependency("howl_session", .{ .target = target, .optimize = optimize });

    const protocol_module = b.addModule("howl_server_protocol", .{
        .root_source_file = b.path("src/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });
    const module = b.addModule("howl_server", .{
        .root_source_file = b.path("src/howl_server.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_session", session.module("howl_session"));
    module.addImport("howl_server_protocol", protocol_module);
    module.addImport("howl_session_endpoint", session.module("howl_session_endpoint"));

    const module_tests = b.addTest(.{
        .name = "howl-server-module",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const protocol_tests = b.addTest(.{
        .name = "howl-server-protocol",
        .root_module = protocol_module,
        .use_llvm = false,
        .use_lld = false,
    });
    const server_tests_root = b.createModule(.{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    server_tests_root.addImport("howl_session", session.module("howl_session"));
    server_tests_root.addImport("howl_session_endpoint", session.module("howl_session_endpoint"));
    const server_tests = b.addTest(.{
        .name = "howl-server-collection",
        .root_module = server_tests_root,
        .use_llvm = false,
        .use_lld = false,
    });

    const check = b.step("check", "Compile the bounded Howl Session collection owner");
    check.dependOn(&module_tests.step);
    check.dependOn(&protocol_tests.step);
    check.dependOn(&server_tests.step);

    const test_step = b.step("test", "Run Howl server collection and manager-wire proofs");
    test_step.dependOn(&b.addRunArtifact(protocol_tests).step);
    test_step.dependOn(&b.addRunArtifact(server_tests).step);
    b.default_step = check;
}
