//! Proves Howl through its distribution root, as an ordinary external consumer.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const howl = b.dependency("howl", .{ .target = target, .optimize = optimize });
    const root = b.createModule(.{
        .root_source_file = b.path("consumer.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Import every public child module through the parent without rebuilding it.
    for (howl.builder.modules.keys()) |name| root.addImport(name, howl.module(name));
    // Resolve every published binary/object through the same external API.
    for (howl.builder.getInstallStep().dependencies.items) |step| {
        const install = step.cast(std.Build.Step.InstallArtifact) orelse continue;
        std.debug.assert(howl.artifact(install.artifact.name) == install.artifact);
    }
    const tests = b.addTest(.{
        .name = "howl-external-consumer",
        .root_module = root,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the external consumer contract");
    check.dependOn(&tests.step);
    b.step("test", "Run the external consumer contract").dependOn(&b.addRunArtifact(tests).step);
    b.default_step = check;
}
