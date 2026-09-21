const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const server = b.dependency("server", .{ .target = target, .optimize = optimize });
    const transport = b.dependency("client_transport", .{ .target = target, .optimize = optimize });

    const module = b.addModule("server_client", .{
        .root_source_file = b.path("src/server_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("server_protocol", server.module("server_protocol"));
    module.addImport("client_transport", transport.module("client_transport"));

    const test_root = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_root.addImport("server_client", module);
    test_root.addImport("server_model", server.module("server"));
    test_root.addImport("server_service", server.module("server_service"));
    test_root.addImport("client_transport", transport.module("client_transport"));
    const tests = b.addTest(.{
        .name = "server-client",
        .root_module = test_root,
        .use_llvm = false,
        .use_lld = false,
    });

    const check = b.step("check", "Compile Server control client");
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run Server control client proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    b.default_step = check;
}
