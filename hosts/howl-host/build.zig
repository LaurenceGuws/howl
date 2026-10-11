const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const headers = b.addWriteFiles();
    const renderer_header = headers.add("renderer-native.h",
        \\#ifdef _FORTIFY_SOURCE
        \\#undef _FORTIFY_SOURCE
        \\#endif
        \\#define _FORTIFY_SOURCE 0
        \\#include <xf86drm.h>
        \\#include <fcntl.h>
        \\#include <unistd.h>
        \\#include <errno.h>
        \\#include <poll.h>
        \\#include <time.h>
        \\#include <sys/stat.h>
        \\#include <sys/sysmacros.h>
    );
    const host_header = headers.add("host-native.h",
        \\#ifdef _FORTIFY_SOURCE
        \\#undef _FORTIFY_SOURCE
        \\#endif
        \\#define _FORTIFY_SOURCE 0
        \\#include <sys/eventfd.h>
        \\#include <sys/mman.h>
        \\#include <unistd.h>
        \\#include <errno.h>
        \\#include <poll.h>
    );
    const renderer_translate = b.addTranslateC(.{
        .root_source_file = renderer_header,
        .target = target,
        .optimize = optimize,
    });
    renderer_translate.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });
    const host_translate = b.addTranslateC(.{
        .root_source_file = host_header,
        .target = target,
        .optimize = optimize,
    });
    const host_c = host_translate.createModule();

    const instance = b.dependency("howl_instance", .{ .target = target, .optimize = optimize });
    const vk = b.dependency("howl_vk", .{ .target = target, .optimize = optimize });
    const wayland = b.dependency("howl_wayland", .{ .target = target, .optimize = optimize });
    const local_terminal = b.createModule(.{
        .root_source_file = b.path("src/local_terminal.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const presentation = b.createModule(.{
        .root_source_file = b.path("src/presentation.zig"),
        .target = target,
        .optimize = optimize,
    });
    const scrollback = b.createModule(.{
        .root_source_file = b.path("src/scrollback.zig"),
        .target = target,
        .optimize = optimize,
    });
    presentation.addImport("howl_instance", instance.module("howl_instance"));
    local_terminal.addImport("host_c", host_c);
    local_terminal.addImport("howl_instance", instance.module("howl_instance"));
    local_terminal.addImport("host_presentation", presentation);
    local_terminal.addImport("host_scrollback", scrollback);
    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root.addImport("howl_vk", vk.module("howl_vk"));
    root.addImport("howl_wayland", wayland.module("howl_wayland"));
    root.addImport("howl_instance", instance.module("howl_instance"));
    root.addImport("local_terminal", local_terminal);
    root.addImport("host_presentation", presentation);
    root.addImport("host_scrollback", scrollback);
    root.addImport("renderer_c", renderer_translate.createModule());
    root.addImport("host_c", host_c);
    root.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });
    root.linkSystemLibrary("vulkan", .{});
    root.linkSystemLibrary("drm", .{});

    const executable = b.addExecutable(.{
        .name = "howl-host",
        .root_module = root,
        .use_llvm = false,
        .use_lld = false,
    });
    b.installArtifact(executable);

    const check = b.step("check", "Compile the native Vulkan performance host");
    check.dependOn(&executable.step);
    const run = b.addRunArtifact(executable);
    run.addPassthruArgs();
    b.step("run", "Run the native Vulkan performance host").dependOn(&run.step);

    const shared = b.createModule(.{
        .root_source_file = b.path("src/shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    shared.addImport("host_c", host_c);
    shared.addImport("howl_wayland", wayland.module("howl_wayland"));
    shared.addImport("howl_instance", instance.module("howl_instance"));
    const test_module = b.createModule(.{
        .root_source_file = b.path("test/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_module.addImport("shared", shared);
    test_module.addImport("host_c", host_c);
    test_module.addImport("howl_wayland", wayland.module("howl_wayland"));
    const tests = b.addTest(.{
        .name = "howl-host-runtime",
        .root_module = test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&tests.step);
    const local_terminal_tests = b.addTest(.{
        .name = "howl-host-local-terminal",
        .root_module = local_terminal,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&local_terminal_tests.step);

    const layout_tests = b.addTest(.{
        .name = "howl-host-layout",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/layout.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&layout_tests.step);

    const key_repeat_tests = b.addTest(.{
        .name = "howl-host-key-repeat",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/key_repeat.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&key_repeat_tests.step);

    const scrollback_tests = b.addTest(.{
        .name = "howl-host-scrollback",
        .root_module = scrollback,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&scrollback_tests.step);

    const input_test_module = b.createModule(.{
        .root_source_file = b.path("src/input_owner.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    input_test_module.addImport("howl_wayland", wayland.module("howl_wayland"));
    input_test_module.addImport("howl_instance", instance.module("howl_instance"));
    input_test_module.addImport("local_terminal", local_terminal);
    input_test_module.addImport("host_scrollback", scrollback);
    input_test_module.addImport("host_c", host_c);
    const input_tests = b.addTest(.{
        .name = "howl-host-input",
        .root_module = input_test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&input_tests.step);

    const published_scene_module = b.createModule(.{
        .root_source_file = b.path("src/published_scene.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    published_scene_module.addImport("host_c", host_c);
    published_scene_module.addImport("howl_vk", vk.module("howl_vk"));
    published_scene_module.addImport("howl_instance", instance.module("howl_instance"));
    published_scene_module.linkSystemLibrary("vulkan", .{});
    const published_scene_tests = b.addTest(.{
        .name = "howl-host-published-scene",
        .root_module = published_scene_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&published_scene_tests.step);

    const test_step = b.step("test", "Run native host runtime ownership proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(local_terminal_tests).step);
    test_step.dependOn(&b.addRunArtifact(layout_tests).step);
    test_step.dependOn(&b.addRunArtifact(key_repeat_tests).step);
    test_step.dependOn(&b.addRunArtifact(scrollback_tests).step);
    test_step.dependOn(&b.addRunArtifact(input_tests).step);
    test_step.dependOn(&b.addRunArtifact(published_scene_tests).step);
    b.default_step = check;
}
