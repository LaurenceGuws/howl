const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("client_transport", .{
        .root_source_file = b.path("src/transport.zig"),
        .target = target,
        .optimize = optimize,
    });
    const tests = b.addTest(.{
        .name = "client-transport",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile native Unix/TCP client transport");
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run native Unix/TCP client transport proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    b.default_step = check;
}
