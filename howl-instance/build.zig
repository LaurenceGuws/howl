const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const pty = b.dependency("howl_pty", .{ .target = target, .optimize = optimize });
    const vt = b.dependency("howl_vt", .{ .target = target, .optimize = optimize });

    const module = b.addModule("howl_instance", .{
        .root_source_file = b.path("src/instance.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_pty", pty.module("howl_pty"));
    module.addImport("howl_vt", vt.module("howl_vt"));

    const tests = b.addTest(.{
        .name = "howl-instance",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });

    const service_module = b.addModule("howl_instance_service", .{
        .root_source_file = b.path("src/service.zig"),
        .target = target,
        .optimize = optimize,
    });
    service_module.addImport("howl_instance", module);
    const service_tests = b.addTest(.{
        .name = "howl-instance-service",
        .root_module = service_module,
        .use_llvm = false,
        .use_lld = false,
    });

    const wire_command = b.addSystemCommand(&.{
        "python3",
        "tools/validate_vectors.py",
        "protocol/v10-vectors.json",
    });
    wire_command.setName("howl-instance wire vectors");
    wire_command.setCwd(b.path("."));
    const wire = b.step("wire", "Validate the language-neutral instance wire corpus");
    wire.dependOn(&wire_command.step);

    const check = b.step("check", "Compile one canonical PTY and VT instance");
    check.dependOn(wire);
    check.dependOn(&tests.step);
    check.dependOn(&service_tests.step);

    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    const test_step = b.step("test", "Run canonical instance ownership proofs");
    test_step.dependOn(wire);
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&b.addRunArtifact(service_tests).step);
    b.default_step = check;
}
