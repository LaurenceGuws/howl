const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const session = b.dependency("howl_session", .{ .target = target, .optimize = optimize });
    const client = b.dependency("howl_client", .{ .target = target, .optimize = optimize });

    const module = b.addModule("howl_cli", .{
        .root_source_file = b.path("src/howl_cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_session", session.module("howl_session"));
    module.addImport("howl_client", client.module("howl_client"));

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    root.addImport("howl_cli", module);
    root.addImport("howl_client", client.module("howl_client"));
    root.addImport("howl_session", session.module("howl_session"));
    const executable = b.addExecutable(.{ .name = "howl", .root_module = root });
    b.installArtifact(executable);

    const tests = b.addTest(.{
        .name = "howl-cli",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the native Howl session client");
    check.dependOn(&executable.step);
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run native Howl CLI proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const composition = b.addSystemCommand(&.{ "python3", "test/composition.py" });
    composition.setName("howl CLI canonical state composition");
    composition.setCwd(b.path("."));
    composition.addArtifactArg(executable);
    composition.addArtifactArg(session.artifact("howl-sessiond"));
    test_step.dependOn(&composition.step);
    const observability = b.addSystemCommand(&.{ "python3", "test/interaction_observability.py" });
    observability.setName("howl CLI interaction observability");
    observability.setCwd(b.path("."));
    observability.addArtifactArg(executable);
    observability.addArtifactArg(session.artifact("howl-sessiond"));
    test_step.dependOn(&observability.step);
    b.default_step = check;
}
