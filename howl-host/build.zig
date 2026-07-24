const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const measure = b.option(bool, "measure", "Enable private host performance counters") orelse false;
    const options = b.addOptions();
    options.addOption(bool, "measure", measure);
    const control = b.dependency("howl_control", .{ .target = target, .optimize = optimize });
    const render = b.dependency("howl_render", .{
        .target = target,
        .optimize = optimize,
        .terminal = true,
        .native_text = true,
        .generated_glyphs = true,
    });
    const native = nativeModules(b, target, optimize);
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_control", control.module("howl_control"));
    module.addImport("howl_render", render.module("howl_render"));
    module.addOptions("host_options", options);
    configureNative(b, module, native);

    const executable = b.addExecutable(.{
        .name = "howl-host",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    b.installArtifact(executable);

    const tests = b.addTest(.{
        .name = "howl-host",
        .root_module = testModule(b, target, optimize, control, render, native, options),
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the control-backed host and proofs");
    check.dependOn(&executable.step);
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    const test_step = b.step("test", "Run the control-backed host proofs");
    test_step.dependOn(&run_tests.step);

    const run = b.addRunArtifact(executable);
    run.step.dependOn(b.getInstallStep());
    run.addPassthruArgs();
    b.step("run", "Run the control-backed host").dependOn(&run.step);
    b.default_step = b.getInstallStep();
}

fn testModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    control: *std.Build.Dependency,
    render: *std.Build.Dependency,
    native: NativeModules,
    options: *std.Build.Step.Options,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_control", control.module("howl_control"));
    module.addImport("howl_render", render.module("howl_render"));
    module.addOptions("host_options", options);
    configureNative(b, module, native);
    return module;
}

const NativeModules = struct {
    clipboard: *std.Build.Module,
    renderer: *std.Build.Module,
    window: *std.Build.Module,
};

fn configureNative(b: *std.Build, module: *std.Build.Module, native: NativeModules) void {
    module.addImport("clipboard_c", native.clipboard);
    module.addImport("renderer_c", native.renderer);
    module.addImport("window_c", native.window);
    configureDevice(module);
    module.addIncludePath(b.path("vendor/xdg-shell"));
    module.addCSourceFile(.{
        .file = b.path("vendor/xdg-shell/xdg-shell-protocol.c"),
        .flags = &.{"-std=c11"},
    });
    module.addIncludePath(b.path("vendor/xdg-system-bell"));
    module.addCSourceFile(.{
        .file = b.path("vendor/xdg-system-bell/xdg-system-bell-v1-protocol.c"),
        .flags = &.{"-std=c11"},
    });
    module.addIncludePath(b.path("vendor/cursor-shape"));
    module.addCSourceFile(.{
        .file = b.path("vendor/cursor-shape/cursor-shape-v1-protocol.c"),
        .flags = &.{"-std=c11"},
    });
    module.linkSystemLibrary("wayland-client", .{});
}

fn nativeModules(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) NativeModules {
    const headers = b.addWriteFiles();
    const clipboard_header = headers.add("howl-host-clipboard.h",
        \\#define _FORTIFY_SOURCE 0
        \\#define _GNU_SOURCE 1
        \\#include <fcntl.h>
        \\#include <sys/random.h>
        \\#include <unistd.h>
        \\
    );
    const clipboard_translate = b.addTranslateC(.{
        .root_source_file = clipboard_header,
        .target = target,
        .optimize = optimize,
    });

    const renderer_header = headers.add("howl-host-renderer.h",
        \\#define _FORTIFY_SOURCE 0
        \\#include <EGL/egl.h>
        \\#include <GLES2/gl2.h>
        \\#include <sys/eventfd.h>
        \\#include <unistd.h>
        \\#include <wayland-client.h>
        \\#include <wayland-egl.h>
        \\
    );
    const renderer_translate = b.addTranslateC(.{
        .root_source_file = renderer_header,
        .target = target,
        .optimize = optimize,
    });
    renderer_translate.linkSystemLibrary("wayland-egl", .{});
    renderer_translate.linkSystemLibrary("EGL", .{});
    renderer_translate.linkSystemLibrary("GLESv2", .{});

    const window_header = headers.add("howl-host-window.h",
        \\#define _FORTIFY_SOURCE 0
        \\#include <linux/input-event-codes.h>
        \\#include <poll.h>
        \\#include <stdlib.h>
        \\#include <sys/eventfd.h>
        \\#include <sys/mman.h>
        \\#include <sys/timerfd.h>
        \\#include <unistd.h>
        \\#include <wayland-client.h>
        \\#include <cursor-shape-v1-client-protocol.h>
        \\#include <xkbcommon/xkbcommon.h>
        \\#include <xkbcommon/xkbcommon-keysyms.h>
        \\#include <xdg-system-bell-v1-client-protocol.h>
        \\#include <xdg-shell-client-protocol.h>
        \\
    );
    const window_translate = b.addTranslateC(.{
        .root_source_file = window_header,
        .target = target,
        .optimize = optimize,
    });
    window_translate.addIncludePath(b.path("vendor/xdg-shell"));
    window_translate.addIncludePath(b.path("vendor/xdg-system-bell"));
    window_translate.addIncludePath(b.path("vendor/cursor-shape"));
    window_translate.linkSystemLibrary("wayland-client", .{});
    window_translate.linkSystemLibrary("xkbcommon", .{});

    return .{
        .clipboard = clipboard_translate.createModule(),
        .renderer = renderer_translate.createModule(),
        .window = window_translate.createModule(),
    };
}

fn configureDevice(module: *std.Build.Module) void {
    module.link_libc = true;
    module.linkSystemLibrary("wayland-egl", .{});
    module.linkSystemLibrary("EGL", .{});
    module.linkSystemLibrary("GLESv2", .{});
    module.linkSystemLibrary("xkbcommon", .{});
}
