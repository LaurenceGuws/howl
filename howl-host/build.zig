const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const run_font = b.option([]const u8, "font", "Absolute font path passed to the live host");
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
        .terminal = true,
    });
    const pty = b.dependency("howl_pty", .{
        .target = target,
        .optimize = optimize,
    });
    const vk = b.dependency("howl_vk", .{ .target = target, .optimize = optimize });
    const vt = b.dependency("howl_vt", .{
        .target = target,
        .optimize = optimize,
    });
    const wayland = b.dependency("howl_wayland", .{ .target = target, .optimize = optimize });
    root.addImport("howl_render", render.module("howl_render"));
    const chrome_state = b.createModule(.{
        .root_source_file = b.path("src/chrome_state.zig"),
        .target = target,
        .optimize = optimize,
    });
    chrome_state.addImport("howl_render", render.module("howl_render"));
    const input_actions = b.createModule(.{
        .root_source_file = b.path("src/input_actions.zig"),
        .target = target,
        .optimize = optimize,
    });
    input_actions.addImport("chrome_state", chrome_state);
    input_actions.addImport("howl_render", render.module("howl_render"));
    input_actions.addImport("howl_wayland", wayland.module("howl_wayland"));
    const terminal_handoff = b.createModule(.{
        .root_source_file = b.path("src/terminal_handoff.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    terminal_handoff.addImport("howl_render", render.module("howl_render"));
    terminal_handoff.addImport("howl_vt", vt.module("howl_vt"));
    terminal_handoff.addImport("howl_wayland", wayland.module("howl_wayland"));
    terminal_handoff.addImport("host_c", host_c);
    const terminal_pool = b.createModule(.{
        .root_source_file = b.path("src/terminal_pool.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_pool.addImport("howl_render", render.module("howl_render"));
    terminal_handoff.addImport("terminal_pool", terminal_pool);
    const terminal_font_owner = b.createModule(.{
        .root_source_file = b.path("src/terminal_font_owner.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_font_owner.addImport("howl_render", render.module("howl_render"));
    const terminal_runtime = b.createModule(.{
        .root_source_file = b.path("src/terminal.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_runtime.addImport("howl_pty", pty.module("howl_pty"));
    terminal_runtime.addImport("howl_render", render.module("howl_render"));
    terminal_runtime.addImport("howl_vt", vt.module("howl_vt"));
    terminal_runtime.addImport("howl_wayland", wayland.module("howl_wayland"));
    terminal_runtime.addImport("terminal_handoff", terminal_handoff);
    terminal_runtime.addImport("terminal_pool", terminal_pool);
    const terminal_runtime_facts = b.addOptions();
    terminal_runtime_facts.addOption(
        []const u8,
        "font_path",
        run_font orelse b.root.joinString(
            b.allocator,
            "../howl-render/testdata/primary.ttf",
        ) catch @panic("OOM"),
    );
    terminal_runtime.addImport(
        "terminal_runtime_facts",
        terminal_runtime_facts.createModule(),
    );
    root.addImport("terminal_handoff", terminal_handoff);
    root.addImport("terminal_runtime", terminal_runtime);
    root.addImport("chrome_state", chrome_state);
    root.addImport("input_actions", input_actions);
    root.addImport("howl_vk", vk.module("howl_vk"));
    root.addImport("howl_wayland", wayland.module("howl_wayland"));
    root.addImport("renderer_c", renderer_translate.createModule());
    root.addImport("host_c", host_c);
    root.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });
    root.linkSystemLibrary("vulkan", .{});
    root.linkSystemLibrary("drm", .{});
    const executable = b.addExecutable(.{ .name = "howl-host", .root_module = root, .use_llvm = false, .use_lld = false });
    b.installArtifact(executable);

    const check = b.step("check", "Compile the host");
    check.dependOn(&executable.step);
    const terminal_pool_check = b.addObject(.{
        .name = "howl-host-terminal-pool-check",
        .root_module = terminal_pool,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&terminal_pool_check.step);
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
    test_shared.addImport("howl_wayland", wayland.module("howl_wayland"));
    test_module.addImport("shared", test_shared);
    test_module.addImport("host_c", host_c);
    test_module.addImport("chrome_state", chrome_state);
    test_module.addImport("input_actions", input_actions);
    test_module.addImport("terminal_handoff", terminal_handoff);
    test_module.addImport("terminal_pool", terminal_pool);
    test_module.addImport("terminal_runtime", terminal_runtime);
    test_module.addImport("howl_render", render.module("howl_render"));
    test_module.addImport("howl_vt", vt.module("howl_vt"));
    test_module.addImport("howl_wayland", wayland.module("howl_wayland"));
    const tests = b.addTest(.{ .root_module = test_module, .use_llvm = false, .use_lld = false });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run deterministic host-owner proofs");
    test_step.dependOn(&run_tests.step);
    const renderer_test_module = b.createModule(.{
        .root_source_file = b.path("src/renderer.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    renderer_test_module.addImport("terminal_handoff", terminal_handoff);
    renderer_test_module.addImport("chrome_state", chrome_state);
    renderer_test_module.addImport("input_actions", input_actions);
    renderer_test_module.addImport("howl_render", render.module("howl_render"));
    renderer_test_module.addImport("howl_vk", vk.module("howl_vk"));
    renderer_test_module.addImport("howl_wayland", wayland.module("howl_wayland"));
    renderer_test_module.addImport("renderer_c", renderer_translate.createModule());
    renderer_test_module.addImport("host_c", host_c);
    renderer_test_module.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });
    renderer_test_module.linkSystemLibrary("vulkan", .{});
    renderer_test_module.linkSystemLibrary("drm", .{});
    const renderer_tests = b.addTest(.{
        .root_module = renderer_test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    test_step.dependOn(&b.addRunArtifact(renderer_tests).step);
    const chrome_tests = b.addTest(.{ .root_module = chrome_state, .use_llvm = false, .use_lld = false });
    const run_chrome_tests = b.addRunArtifact(chrome_tests);
    test_step.dependOn(&run_chrome_tests.step);
    const input_action_tests = b.addTest(.{ .root_module = input_actions, .use_llvm = false, .use_lld = false });
    test_step.dependOn(&b.addRunArtifact(input_action_tests).step);
    const handoff_tests = b.addTest(.{
        .root_module = terminal_handoff,
        .use_llvm = false,
        .use_lld = false,
    });
    test_step.dependOn(&b.addRunArtifact(handoff_tests).step);
    const terminal_pool_tests = b.addTest(.{
        .root_module = terminal_pool,
        .use_llvm = false,
        .use_lld = false,
    });
    const run_terminal_pool_tests = b.addRunArtifact(terminal_pool_tests);
    test_step.dependOn(&run_terminal_pool_tests.step);
    b.step("test-pool", "Run fixed terminal pool storage proofs")
        .dependOn(&run_terminal_pool_tests.step);
    const terminal_font_owner_tests = b.addTest(.{
        .root_module = terminal_font_owner,
        .use_llvm = false,
        .use_lld = false,
    });
    test_step.dependOn(&b.addRunArtifact(terminal_font_owner_tests).step);
    const terminal_runtime_tests = b.addTest(.{
        .root_module = terminal_runtime,
        .use_llvm = false,
        .use_lld = false,
    });
    test_step.dependOn(&b.addRunArtifact(terminal_runtime_tests).step);
    const terminal_contract = b.createModule(.{
        .root_source_file = b.path("test/terminal_contract_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_contract.addImport("chrome_state", chrome_state);
    terminal_contract.addImport("howl_render", render.module("howl_render"));
    terminal_contract.addImport("howl_vt", vt.module("howl_vt"));
    terminal_contract.addImport("terminal_handoff", terminal_handoff);
    const terminal_test_facts = b.addOptions();
    terminal_test_facts.addOption(
        []const u8,
        "font_path",
        b.root.joinString(
            b.allocator,
            "../howl-render/testdata/primary.ttf",
        ) catch @panic("OOM"),
    );
    terminal_contract.addImport("terminal_test_facts", terminal_test_facts.createModule());
    const terminal_contract_tests = b.addTest(.{
        .root_module = terminal_contract,
        .use_llvm = false,
        .use_lld = false,
    });
    test_step.dependOn(&b.addRunArtifact(terminal_contract_tests).step);
    b.default_step = check;
}
