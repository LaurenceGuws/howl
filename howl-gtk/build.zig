const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const session = b.dependency("howl_session", .{ .target = target, .optimize = optimize });
    const text = b.dependency("howl_text", .{ .target = target, .optimize = optimize });

    const client = b.createModule(.{
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
    });
    client.addImport("howl_session", session.module("howl_session"));

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root.addImport("gtk_native", b.createModule(.{ .root_source_file = b.path("src/native.zig"), .target = target, .optimize = optimize }));
    root.addImport("howl_client", client);
    root.addImport("howl_text", text.module("howl_text"));
    root.linkSystemLibrary("gtk4", .{});
    root.addCSourceFile(.{ .file = b.path("src/gtk_shim.c") });

    const executable = b.addExecutable(.{ .name = "howl-gtk", .root_module = root });
    b.installArtifact(executable);

    const client_tests = b.addTest(.{
        .name = "howl-gtk-client",
        .root_module = client,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the experimental GTK session client");
    check.dependOn(&executable.step);
    check.dependOn(&client_tests.step);
    const test_step = b.step("test", "Run bounded GTK client protocol proofs");
    test_step.dependOn(&b.addRunArtifact(client_tests).step);
    b.default_step = check;
}
