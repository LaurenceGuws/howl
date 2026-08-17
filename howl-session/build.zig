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
    const server_module = b.createModule(.{
        .root_source_file = b.path("src/server.zig"),
        .target = target,
        .optimize = optimize,
    });
    server_module.addImport("howl_session", module);
    const server = b.addExecutable(.{ .name = "howl-sessiond", .root_module = server_module });
    const server_tests = b.addTest(.{
        .name = "howl-session-server",
        .root_module = server_module,
        .use_llvm = false,
        .use_lld = false,
    });
    const bridge_module = b.createModule(.{
        .root_source_file = b.path("src/bridge.zig"),
        .target = target,
        .optimize = optimize,
    });
    const bridge = b.addExecutable(.{ .name = "howl-session-bridge", .root_module = bridge_module });
    const bridge_tests = b.addTest(.{
        .name = "howl-session-bridge",
        .root_module = bridge_module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the canonical PTY and VT session owner");
    check.dependOn(&tests.step);
    check.dependOn(&server.step);
    check.dependOn(&server_tests.step);
    check.dependOn(&bridge.step);
    check.dependOn(&bridge_tests.step);
    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    const run_server_tests = b.addRunArtifact(server_tests);
    run_server_tests.addPassthruArgs();
    const run_bridge_tests = b.addRunArtifact(bridge_tests);
    run_bridge_tests.addPassthruArgs();
    const test_step = b.step("test", "Run canonical session ownership proofs");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_server_tests.step);
    test_step.dependOn(&run_bridge_tests.step);
    b.installArtifact(server);
    b.installArtifact(bridge);
    b.default_step = check;
}
