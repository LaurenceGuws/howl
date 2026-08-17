const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const pty = b.dependency("howl_pty", .{ .target = target, .optimize = optimize });
    const vt = b.dependency("howl_vt", .{ .target = target, .optimize = optimize });
    const module = b.addModule("howl_session", .{
        .root_source_file = b.path("src/session.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_pty", pty.module("howl_pty"));
    module.addImport("howl_vt", vt.module("howl_vt"));
    const tests = b.addTest(.{
        .name = "howl-session",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the canonical PTY and VT session owner");
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    b.step("test", "Run canonical session ownership proofs").dependOn(&run_tests.step);
    b.default_step = check;
}
