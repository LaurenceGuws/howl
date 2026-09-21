const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const instance = b.dependency("howl_instance", .{ .target = target, .optimize = optimize });
    const transport = b.dependency("client_transport", .{ .target = target, .optimize = optimize });
    const module = b.addModule("howl_client", .{
        .root_source_file = b.path("src/howl_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_instance", instance.module("howl_instance"));
    module.addImport("client_transport", transport.module("client_transport"));
    const tests = b.addTest(.{
        .name = "howl-client",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the reusable native Howl client");
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run native Howl client framing proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    b.default_step = check;
}
