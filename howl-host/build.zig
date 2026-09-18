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

    const session = b.dependency("howl_session", .{ .target = target, .optimize = optimize });
    const sessiond = session.artifact("howl-sessiond");
    const vk = b.dependency("howl_vk", .{ .target = target, .optimize = optimize });
    const wayland = b.dependency("howl_wayland", .{ .target = target, .optimize = optimize });
    const client_dependency = b.dependency("howl_client", .{ .target = target, .optimize = optimize });
    const client = client_dependency.module("howl_client");
    const text_dependency = b.dependency("howl_text", .{ .target = target, .optimize = optimize });
    const text = text_dependency.module("howl_text");
    const render_dependency = b.dependency("howl_render", .{ .target = target, .optimize = optimize });
    const presentation = b.createModule(.{
        .root_source_file = render_dependency.path("src/presentation.zig"),
        .target = target,
        .optimize = optimize,
    });
    const terminal = b.createModule(.{
        .root_source_file = render_dependency.path("src/terminal.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal.addImport("howl_client", client);
    terminal.addImport("howl_text", text);

    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root.addImport("howl_vk", vk.module("howl_vk"));
    root.addImport("howl_wayland", wayland.module("howl_wayland"));
    root.addImport("howl_client", client);
    root.addImport("howl_session", session.module("howl_session"));
    root.addImport("howl_text", text);
    root.addImport("presentation", presentation);
    root.addImport("terminal", terminal);
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
    // The Host resolves this exact sibling artifact at runtime for Sessions it
    // owns. Attaching to externally supplied endpoints remains unchanged.
    b.installArtifact(sessiond);

    const check = b.step("check", "Compile the native Vulkan performance host");
    check.dependOn(&executable.step);
    check.dependOn(&sessiond.step);
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
    shared.addImport("howl_session", session.module("howl_session"));
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

    const scrollback_tests = b.addTest(.{
        .name = "howl-host-scrollback",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/scrollback.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
    input_test_module.addImport("howl_client", client);
    input_test_module.addImport("howl_wayland", wayland.module("howl_wayland"));
    input_test_module.addImport("howl_session", session.module("howl_session"));
    input_test_module.addImport("host_c", host_c);
    const input_tests = b.addTest(.{
        .name = "howl-host-input",
        .root_module = input_test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&input_tests.step);

    const fast_test_module = b.createModule(.{
        .root_source_file = b.path("src/terminal_fast.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    fast_test_module.addImport("howl_client", client);
    fast_test_module.addImport("howl_text", text);
    fast_test_module.addImport("howl_vk", vk.module("howl_vk"));
    const fast_test_fonts = b.addOptions();
    fast_test_fonts.addOption(
        []const u8,
        "primary_font",
        b.root.joinString(b.allocator, "../howl-text/testdata/primary.ttf") catch @panic("OOM"),
    );
    const test_fonts = fast_test_fonts.createModule();
    fast_test_module.addImport("test_fonts", test_fonts);
    fast_test_module.linkSystemLibrary("vulkan", .{});
    const fast_tests = b.addTest(.{
        .name = "howl-host-terminal-fast",
        .root_module = fast_test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&fast_tests.step);

    const scene_test_module = b.createModule(.{
        .root_source_file = b.path("src/terminal_scene.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    scene_test_module.addImport("howl_vk", vk.module("howl_vk"));
    scene_test_module.addImport("howl_client", client);
    scene_test_module.addImport("howl_text", text);
    scene_test_module.addImport("presentation", presentation);
    scene_test_module.addImport("terminal", terminal);
    scene_test_module.addImport("test_fonts", test_fonts);
    scene_test_module.linkSystemLibrary("vulkan", .{});
    const scene_tests = b.addTest(.{
        .name = "howl-host-terminal-scene",
        .root_module = scene_test_module,
        .filters = &.{"terminal scene"},
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&scene_tests.step);

    const test_step = b.step("test", "Run native host runtime ownership proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(layout_tests).step);
    test_step.dependOn(&b.addRunArtifact(scrollback_tests).step);
    test_step.dependOn(&b.addRunArtifact(input_tests).step);
    test_step.dependOn(&b.addRunArtifact(fast_tests).step);
    test_step.dependOn(&b.addRunArtifact(scene_tests).step);
    b.default_step = check;
}
