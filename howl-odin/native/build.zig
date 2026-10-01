const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const client_dependency = b.dependency("howl_client", .{ .target = target, .optimize = optimize });
    const server_client_dependency = b.dependency("server_client", .{ .target = target, .optimize = optimize });
    const render_dependency = b.dependency("howl_render", .{
        .target = target,
        .optimize = optimize,
        // Linux uses the installed text stack. Cross-target clients use the
        // pinned memory-only FreeType/HarfBuzz sources already owned by Howl.
        .bundled_text = target.result.os.tag != .linux,
    });
    const root = b.createModule(.{
        .root_source_file = b.path("bridge.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    root.addImport("howl_client", client_dependency.module("howl_client"));
    root.addImport("howl_local", client_dependency.module("howl_local"));
    root.addImport("server_client", server_client_dependency.module("server_client"));
    root.addImport("howl_render", render_dependency.module("howl_render"));

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
    const test_step = b.step("test", "Run Odin bridge ownership and mapping proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}
