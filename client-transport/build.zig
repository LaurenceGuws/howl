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
    // Separate process so the proof, not the reusable library, owns SIGPIPE.
    const sigpipe_root = b.createModule(.{
        .root_source_file = b.path("test/sigpipe.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    sigpipe_root.addImport("client_transport", module);
    const sigpipe = b.addExecutable(.{ .name = "transport-sigpipe", .root_module = sigpipe_root });
    check.dependOn(&sigpipe.step);
    test_step.dependOn(&b.addRunArtifact(sigpipe).step);
    b.default_step = check;
}
