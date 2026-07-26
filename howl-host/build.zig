const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const run_font = b.option([]const u8, "font", "Absolute font path passed to the live host");
    const headers = b.addWriteFiles();
    const window_header = headers.add("window-native.h",
        \\#ifdef _FORTIFY_SOURCE
        \\#undef _FORTIFY_SOURCE
        \\#endif
        \\#define _FORTIFY_SOURCE 0
        \\#include <wayland-client.h>
        \\#include "xdg-shell-client-protocol.h"
        \\#include "linux-dmabuf-v1-client-protocol.h"
        \\#include "linux-drm-syncobj-v1-client-protocol.h"
        \\#include <sys/mman.h>
        \\#include <unistd.h>
        \\#include <poll.h>
        \\#include <errno.h>
    );
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
        \\#include <unistd.h>
        \\#include <errno.h>
        \\#include <poll.h>
    );
    const window_translate = b.addTranslateC(.{ .root_source_file = window_header, .target = target, .optimize = optimize });
    window_translate.addIncludePath(b.path("vendor/xdg-shell"));
    window_translate.addIncludePath(b.path("vendor/linux-dmabuf"));
    window_translate.addIncludePath(b.path("vendor/linux-drm-syncobj"));
    const renderer_translate = b.addTranslateC(.{ .root_source_file = renderer_header, .target = target, .optimize = optimize });
    renderer_translate.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });
    const host_translate = b.addTranslateC(.{ .root_source_file = host_header, .target = target, .optimize = optimize });
    const host_c = host_translate.createModule();
    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const render = b.dependency("howl_render", .{
        .target = target,
        .optimize = optimize,
        .native_text = true,
        .generated_glyphs = false,
        .terminal = false,
    });
    root.addImport("howl_render", render.module("howl_render"));
    const chrome_state = b.createModule(.{
        .root_source_file = b.path("src/chrome_state.zig"),
        .target = target,
        .optimize = optimize,
    });
    chrome_state.addImport("howl_render", render.module("howl_render"));
    const chrome_draw = b.createModule(.{
        .root_source_file = b.path("src/chrome_draw.zig"),
        .target = target,
        .optimize = optimize,
    });
    chrome_draw.addImport("howl_render", render.module("howl_render"));
    const chrome_options = b.addOptions();
    chrome_options.addOption([]const u8, "test_font_path", b.root.joinString(b.allocator, "../howl-render/testdata/primary.ttf") catch @panic("OOM"));
    chrome_draw.addImport("host_build_options", chrome_options.createModule());
    const vulkan = b.createModule(.{
        .root_source_file = b.path("vendor/vulkan/vulkan.zig"),
        .target = target,
        .optimize = optimize,
    });
    const gpu_chrome = b.createModule(.{
        .root_source_file = b.path("src/gpu_chrome.zig"),
        .target = target,
        .optimize = optimize,
    });
    gpu_chrome.addImport("chrome_draw", chrome_draw);
    gpu_chrome.addImport("vulkan", vulkan);
    root.addImport("chrome_state", chrome_state);
    root.addImport("chrome_draw", chrome_draw);
    root.addImport("gpu_chrome", gpu_chrome);
    root.addImport("window_c", window_translate.createModule());
    root.addImport("renderer_c", renderer_translate.createModule());
    root.addImport("host_c", host_c);
    root.addImport("vulkan", vulkan);
    root.addCSourceFiles(.{
        .root = b.path("vendor"),
        .files = &.{
            "xdg-shell/xdg-shell-protocol.c",
            "linux-dmabuf/linux-dmabuf-v1-protocol.c",
            "linux-drm-syncobj/linux-drm-syncobj-v1-protocol.c",
        },
        .flags = &.{},
    });
    root.addIncludePath(b.path("vendor/xdg-shell"));
    root.addIncludePath(b.path("vendor/linux-dmabuf"));
    root.addIncludePath(b.path("vendor/linux-drm-syncobj"));
    root.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });
    root.linkSystemLibrary("wayland-client", .{});
    root.linkSystemLibrary("vulkan", .{});
    root.linkSystemLibrary("drm", .{});
    const executable = b.addExecutable(.{ .name = "howl-host", .root_module = root, .use_llvm = false, .use_lld = false });
    b.installArtifact(executable);

    const check = b.step("check", "Compile the host");
    check.dependOn(&executable.step);
    const run = b.addRunArtifact(executable);
    if (run_font) |font| run.addArgs(&.{ "--font", font });
    b.step("run", "Run the bounded live color ring").dependOn(&run.step);

    const test_module = b.createModule(.{
        .root_source_file = b.path("test/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const test_shared = b.createModule(.{
        .root_source_file = b.path("src/shared.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_shared.addImport("host_c", host_c);
    test_module.addImport("shared", test_shared);
    test_module.addImport("host_c", host_c);
    test_module.addImport("chrome_state", chrome_state);
    test_module.addImport("howl_render", render.module("howl_render"));
    const tests = b.addTest(.{ .root_module = test_module, .use_llvm = false, .use_lld = false });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run deterministic host-owner proofs");
    test_step.dependOn(&run_tests.step);
    const chrome_tests = b.addTest(.{ .root_module = chrome_state, .use_llvm = false, .use_lld = false });
    const run_chrome_tests = b.addRunArtifact(chrome_tests);
    test_step.dependOn(&run_chrome_tests.step);
    const draw_tests = b.addTest(.{ .root_module = chrome_draw, .use_llvm = false, .use_lld = false });
    test_step.dependOn(&b.addRunArtifact(draw_tests).step);
    b.default_step = check;
}
