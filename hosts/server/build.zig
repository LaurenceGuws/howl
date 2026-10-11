//! Builds optional Server hosting policy for the existing howl CLI.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const server = b.dependency("server", .{ .target = target, .optimize = optimize });
    const instance = b.dependency("howl_instance", .{ .target = target, .optimize = optimize });
    const runtime = b.addModule("server_runtime", .{
        .root_source_file = b.path("src/runtime.zig"),
        .target = target,
        .optimize = optimize,
    });
    runtime.addImport("server_model", server.module("server"));
    runtime.addImport("server_service", server.module("server_service"));
    runtime.addImport("howl_instance", instance.module("howl_instance"));
    const proofs = b.addTest(.{
        .name = "server-runtime",
        .root_module = runtime,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the optional Server host runtime");
    check.dependOn(&proofs.step);
    b.step("test", "Run Server listener and scheduling proofs").dependOn(&b.addRunArtifact(proofs).step);
    b.default_step = check;
}
