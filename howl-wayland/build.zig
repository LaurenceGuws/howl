const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const header = b.path("src/wayland-native.h");
    const translate = b.addTranslateC(.{ .root_source_file = header, .target = target, .optimize = optimize });
    translate.addIncludePath(b.path("protocol/xdg-shell"));
    translate.addIncludePath(b.path("protocol/linux-dmabuf"));
    translate.addIncludePath(b.path("protocol/linux-drm-syncobj"));
    translate.addIncludePath(b.path("protocol/fractional-scale"));
    translate.addIncludePath(b.path("protocol/viewporter"));
    const xkb_translate = b.addTranslateC(.{ .root_source_file = b.path("src/xkb-native.h"), .target = target, .optimize = optimize });
    const module = b.addModule("howl_wayland", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addImport("wayland_c", translate.createModule());
    module.addCSourceFiles(.{
        .root = b.path("protocol"),
        .files = &.{
            "xdg-shell/xdg-shell-protocol.c",
            "linux-dmabuf/linux-dmabuf-v1-protocol.c",
            "linux-drm-syncobj/linux-drm-syncobj-v1-protocol.c",
            "fractional-scale/fractional-scale-v1-protocol.c",
            "viewporter/viewporter-protocol.c",
        },
        .flags = &.{},
    });
    module.addIncludePath(b.path("protocol/xdg-shell"));
    module.addIncludePath(b.path("protocol/linux-dmabuf"));
    module.addIncludePath(b.path("protocol/linux-drm-syncobj"));
    module.addIncludePath(b.path("protocol/fractional-scale"));
    module.addIncludePath(b.path("protocol/viewporter"));
    module.linkSystemLibrary("wayland-client", .{});
    module.linkSystemLibrary("xkbcommon", .{});
    module.addImport("xkb_c", xkb_translate.createModule());
    const proof = b.createModule(.{
        .root_source_file = b.path("src/proofs.zig"),
        .target = target,
        .optimize = optimize,
    });
    proof.addImport("howl_wayland", module);
    const tests = b.addTest(.{ .root_module = proof, .use_llvm = false, .use_lld = false });
    tests.root_module.linkSystemLibrary("wayland-client", .{});
    tests.root_module.linkSystemLibrary("xkbcommon", .{});
    const check = b.step("check", "Compile the Wayland package");
    check.dependOn(&tests.step);
    const test_step = b.step("test", "Run Wayland ownership and input proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const reproducibility = b.step("reproducibility", "Verify wayland-scanner output");
    reproducibility.dependOn(&b.addSystemCommand(&.{ "sh", "tools/verify_generated.sh" }).step);
    check.dependOn(reproducibility);
    b.default_step = check;
}
