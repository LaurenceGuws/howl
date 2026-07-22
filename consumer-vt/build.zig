const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const vt = b.dependency("howl_vt", .{ .target = target, .optimize = optimize });
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_vt", vt.module("howl_vt"));
    const proof = b.addTest(.{ .name = "howl-vt-consumer", .root_module = module });
    proof.use_llvm = true;
    const check = b.step("check", "Compile the external VT consumer proof");
    check.dependOn(&proof.step);
    const run = b.addRunArtifact(proof);
    b.step("test", "Run the external VT consumer proof").dependOn(&run.step);
    b.default_step = check;
}
