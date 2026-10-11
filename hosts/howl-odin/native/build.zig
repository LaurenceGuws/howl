const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const client_dependency = b.dependency("howl_client", .{
        .target = target,
        .optimize = optimize,
        .bundled_render_text = target.result.os.tag != .linux,
    });
    const server_client_dependency = b.dependency("server_client", .{ .target = target, .optimize = optimize });
    const root = b.createModule(.{
        .root_source_file = b.path("bridge.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    root.addImport("howl_client", client_dependency.module("howl_client"));
    root.addImport("howl_client_render", client_dependency.module("howl_client_render"));
    const instance_dependency = b.dependency("howl_instance", .{
        .target = target,
        .optimize = optimize,
        .bundled_render_text = target.result.os.tag != .linux,
    });
    root.addImport("test_fonts", instance_dependency.module("howl_text_test_fonts"));
    root.addImport("server_client", server_client_dependency.module("server_client"));

    const library = b.addLibrary(.{
        .name = "howl_odin_bridge",
        .linkage = .dynamic,
        .root_module = root,
    });
    b.installArtifact(library);

    const tests = b.addTest(.{
        .name = "howl-odin-bridge",
        .root_module = root,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the Odin bridge and all its proofs");
    check.dependOn(&library.step);
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run Odin bridge ownership and mapping proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
