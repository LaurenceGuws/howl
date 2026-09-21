const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const session = b.dependency("howl_session", .{ .target = target, .optimize = optimize });
    const client = b.dependency("howl_client", .{ .target = target, .optimize = optimize });
    const server = b.dependency("howl_server", .{ .target = target, .optimize = optimize });

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
    root.addImport("howl_server", server.module("howl_server"));
    const executable = b.addExecutable(.{ .name = "howl", .root_module = root });
    b.installArtifact(executable);

    const tests = b.addTest(.{
        .name = "howl-cli",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const manager_tests_root = b.createModule(.{
        .root_source_file = b.path("src/manager_commands.zig"),
        .target = target,
        .optimize = optimize,
    });
    manager_tests_root.addImport("howl_client", client.module("howl_client"));
    manager_tests_root.addImport("howl_server", server.module("howl_server"));
    const manager_tests = b.addTest(.{
        .name = "howl-cli-manager",
        .root_module = manager_tests_root,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the native Howl session client");
    check.dependOn(&executable.step);
    check.dependOn(&tests.step);
    check.dependOn(&manager_tests.step);
    const test_step = b.step("test", "Run native Howl CLI proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(manager_tests).step);
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
    const ssh_route = b.addSystemCommand(&.{ "python3", "test/ssh_route.py" });
    ssh_route.setName("howl native SSH route failure boundaries");
    ssh_route.setCwd(b.path("."));
    ssh_route.addArtifactArg(executable);
    test_step.dependOn(&ssh_route.step);
    const interface = b.addSystemCommand(&.{ "python3", "test/interface.py" });
    interface.setName("howl CLI interface quality");
    interface.setCwd(b.path("."));
    interface.addArtifactArg(executable);
    test_step.dependOn(&interface.step);
    const server_multi = b.addSystemCommand(&.{ "python3", "test/server_multi.py" });
    server_multi.setName("howl CLI multi-terminal server");
    server_multi.setCwd(b.path("."));
    server_multi.addArtifactArg(executable);
    test_step.dependOn(&server_multi.step);
    b.default_step = check;
}
