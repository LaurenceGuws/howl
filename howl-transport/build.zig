const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const session = b.dependency("howl_session", .{ .target = target, .optimize = optimize });

    const transport = b.addModule("howl_transport", .{
        .root_source_file = b.path("src/transport.zig"),
        .target = target,
        .optimize = optimize,
    });
    transport.addImport("howl_session", session.module("howl_session"));

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root.addImport("howl_transport", transport);
    const executable = b.addExecutable(.{ .name = "howl-transport", .root_module = root });
    b.installArtifact(executable);

    const tests = b.addTest(.{
        .name = "howl-transport",
        .root_module = transport,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the AX transport experiment");
    check.dependOn(&executable.step);
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run AX transport proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const composition = b.addSystemCommand(&.{ "python3", "test/composition.py" });
    composition.setName("howl-transport state-machine composition");
    composition.setCwd(b.path("."));
    composition.addArtifactArg(executable);
    composition.addArtifactArg(session.artifact("howl-sessiond"));
    test_step.dependOn(&composition.step);
    const observability = b.addSystemCommand(&.{ "python3", "test/interaction_observability.py" });
    observability.setName("howl-transport interaction observability");
    observability.setCwd(b.path("."));
    observability.addArtifactArg(executable);
    observability.addArtifactArg(session.artifact("howl-sessiond"));
    test_step.dependOn(&observability.step);
    b.default_step = check;
}
