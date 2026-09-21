const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const instance = b.dependency("howl_instance", .{ .target = target, .optimize = optimize });

    const protocol_module = b.addModule("server_protocol", .{
        .root_source_file = b.path("src/protocol.zig"),
        .target = target,
        .optimize = optimize,
    });
    const protocol_tests = b.addTest(.{
        .name = "server-protocol",
        .root_module = protocol_module,
        .use_llvm = false,
        .use_lld = false,
    });

    const module = b.addModule("server", .{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_instance", instance.module("howl_instance"));
    module.addImport("howl_instance_service", instance.module("howl_instance_service"));

    const tests = b.addTest(.{
        .name = "server",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });

    const check = b.step("check", "Compile Server -> Sessions -> Instances ownership");
    check.dependOn(&tests.step);
    check.dependOn(&protocol_tests.step);
    const test_step = b.step("test", "Run Server -> Sessions -> Instances ownership proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(protocol_tests).step);
    b.default_step = check;
}
