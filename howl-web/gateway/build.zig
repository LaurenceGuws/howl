//! Builds the loopback-only Howl Web HTTP/WebSocket origin.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const exe = b.addExecutable(.{ .name = "howl-web-gateway", .root_module = module });
    b.installArtifact(exe);

    const tests = b.addTest(.{ .name = "howl-web-gateway", .root_module = module });
    const check = b.step("check", "Compile and test bounded gateway policy");
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run bounded gateway policy and live byte-bridge proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const integration = b.addSystemCommand(&.{ "python3", "tests/integration.py" });
    integration.setCwd(b.path("."));
    integration.addFileArg(exe.getEmittedBin());
    integration.setName("loopback gateway integration");
    test_step.dependOn(&integration.step);
    b.default_step = check;
}
