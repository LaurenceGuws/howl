const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const transport = b.dependency("client_transport", .{ .target = target, .optimize = optimize });

    const module = b.addModule("server_client", .{
        .root_source_file = b.path("src/server_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("server_protocol", b.dependency("server_protocol", .{ .target = target, .optimize = optimize }).module("server_protocol"));
    module.addImport("client_transport", transport.module("client_transport"));

    // Server model/service are integration-test fixtures, never client imports.
    const server = b.dependency("server", .{ .target = target, .optimize = optimize });
    const test_root = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_root.addImport("server_client", module);
    test_root.addImport("howl_client", b.dependency("howl_client", .{ .target = target, .optimize = optimize }).module("howl_client"));
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
    const audit = b.step("audit", "Audit every owned Zig source file");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    check.dependOn(audit);
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run Server control client proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    b.default_step = check;
}
