const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const run_command = b.option([]const u8, "command", "One-shot /bin/sh -c command for the first pane");
    const headers = b.addWriteFiles();
    const renderer_header = headers.add("renderer-native.h",
        \\#ifdef _FORTIFY_SOURCE
        \\#undef _FORTIFY_SOURCE
        \\#endif
        \\#define _FORTIFY_SOURCE 0
        \\#include <xf86drm.h>
    );
    const renderer_translate = b.addTranslateC(.{ .root_source_file = renderer_header, .target = target, .optimize = optimize });
    renderer_translate.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });
    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const config_options = b.addOptions();
    config_options.addOption(
        []const u8,
        "repository_config_path",
        b.root.joinString(
            b.allocator,
            "../.howl/config/howl.conf",
        ) catch @panic("OOM"),
    );
    const config = b.createModule(.{
        .root_source_file = b.path("src/config.zig"),
        .target = target,
        .optimize = optimize,
    });
    config.addImport("config_options", config_options.createModule());
    const render = b.dependency("howl_render", .{
        .target = target,
        .optimize = optimize,
        .native_text = true,
    });
    const pty = b.dependency("howl_pty", .{
        .target = target,
        .optimize = optimize,
    });
    const vk = b.dependency("howl_vk", .{
        .target = target,
        .optimize = optimize,
    });
    const vt = b.dependency("howl_vt", .{
        .target = target,
        .optimize = optimize,
    });
    const wayland = b.dependency("howl_wayland", .{ .target = target, .optimize = optimize });
    root.addImport("howl_render", render.module("howl_render"));
    root.addImport("config", config);
    const session_chrome_adapter = b.createModule(.{
        .root_source_file = b.path("src/session_chrome_adapter.zig"),
        .target = target,
        .optimize = optimize,
    });
    session_chrome_adapter.addImport("howl_render", render.module("howl_render"));
    const session_domain = b.createModule(.{
        .root_source_file = b.path("src/session_domain.zig"),
        .target = target,
        .optimize = optimize,
    });
    session_chrome_adapter.addImport("session_domain", session_domain);
    const input_actions = b.createModule(.{
        .root_source_file = b.path("src/input_actions.zig"),
        .target = target,
        .optimize = optimize,
    });
    input_actions.addImport("session_chrome_adapter", session_chrome_adapter);
    input_actions.addImport("session_domain", session_domain);
    input_actions.addImport("howl_render", render.module("howl_render"));
    input_actions.addImport("howl_wayland", wayland.module("howl_wayland"));
    const terminal_handoff = b.createModule(.{
        .root_source_file = b.path("src/terminal_handoff.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    terminal_handoff.addImport("howl_vt", vt.module("howl_vt"));
    terminal_handoff.addImport("howl_wayland", wayland.module("howl_wayland"));
    const terminal_visual_fifo = b.createModule(.{
        .root_source_file = b.path("src/terminal_visual_fifo.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    terminal_visual_fifo.addImport("howl_vt", vt.module("howl_vt"));
    terminal_visual_fifo.addImport("terminal_handoff", terminal_handoff);
    const terminal_fonts = b.createModule(.{
        .root_source_file = b.path("src/terminal_fonts.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_fonts.addImport("howl_render", render.module("howl_render"));
    terminal_fonts.addImport("terminal_handoff", terminal_handoff);
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
    terminal_runtime.addImport("terminal_visual_fifo", terminal_visual_fifo);
    terminal_runtime.addImport("config", config);
    root.addImport("terminal_handoff", terminal_handoff);
    root.addImport("terminal_visual_fifo", terminal_visual_fifo);
    root.addImport("terminal_fonts", terminal_fonts);
    root.addImport("howl_vt", vt.module("howl_vt"));
    root.addImport("terminal_runtime", terminal_runtime);
    root.addImport("session_chrome_adapter", session_chrome_adapter);
    root.addImport("session_domain", session_domain);
    root.addImport("input_actions", input_actions);
    root.addImport("howl_vk", vk.module("howl_vk"));
    root.addImport("howl_wayland", wayland.module("howl_wayland"));
    root.addImport("renderer_c", renderer_translate.createModule());
    root.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });
    root.linkSystemLibrary("vulkan", .{});
    root.linkSystemLibrary("drm", .{});
    const executable = b.addExecutable(.{ .name = "howl-host", .root_module = root, .use_llvm = false, .use_lld = false });
    b.installArtifact(executable);

    const check = b.step("check", "Compile the host");
    check.dependOn(&executable.step);
    const fixture_classifier_module = b.createModule(.{
        .root_source_file = b.path("manual-fixtures/generated-classifier.zig"),
        .target = target,
        .optimize = optimize,
    });
    fixture_classifier_module.addImport(
        "howl_render",
        render.module("howl_render"),
    );
    const fixture_classifier = b.addExecutable(.{
        .name = "howl-generated-fixture-classifier",
        .root_module = fixture_classifier_module,
        .use_llvm = false,
        .use_lld = false,
    });
    const fixture_check = b.addSystemCommand(
        &.{ "sh", "manual-fixtures/check-fixtures.sh" },
    );
    fixture_check.addArtifactArg(fixture_classifier);
    fixture_check.setCwd(b.path("."));
    check.dependOn(&fixture_check.step);
    const run = b.addRunArtifact(executable);
    if (run_command) |command| run.addArgs(&.{ "--command", command });
    b.step("run", "Run the bounded live color ring").dependOn(&run.step);

    const test_module = b.createModule(.{
        .root_source_file = b.path("test/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const test_presentation_state = b.createModule(.{
        .root_source_file = b.path("src/presentation_state.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_presentation_state.addImport("howl_wayland", wayland.module("howl_wayland"));
    test_module.addImport("presentation_state", test_presentation_state);
    test_module.addImport("session_chrome_adapter", session_chrome_adapter);
    test_module.addImport("session_domain", session_domain);
    test_module.addImport("input_actions", input_actions);
    test_module.addImport("terminal_handoff", terminal_handoff);
    test_module.addImport("terminal_visual_fifo", terminal_visual_fifo);
    test_module.addImport("terminal_fonts", terminal_fonts);
    test_module.addImport("terminal_runtime", terminal_runtime);
    test_module.addImport("howl_render", render.module("howl_render"));
    test_module.addImport("howl_vt", vt.module("howl_vt"));
    test_module.addImport("howl_wayland", wayland.module("howl_wayland"));
    const tests = b.addTest(.{ .root_module = test_module, .use_llvm = false, .use_lld = false });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run deterministic host-owner proofs");
    test_step.dependOn(&run_tests.step);
    const config_tests = b.addTest(.{ .root_module = config, .use_llvm = false, .use_lld = false });
    test_step.dependOn(&b.addRunArtifact(config_tests).step);
    test_step.dependOn(&fixture_check.step);
    const window_test_module = b.createModule(.{
        .root_source_file = b.path("src/window.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    window_test_module.addImport("howl_wayland", wayland.module("howl_wayland"));
    const window_tests = b.addTest(.{
        .root_module = window_test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    test_step.dependOn(&b.addRunArtifact(window_tests).step);
    const renderer_test_module = b.createModule(.{
        .root_source_file = b.path("src/renderer.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    renderer_test_module.addImport("terminal_handoff", terminal_handoff);
    renderer_test_module.addImport("terminal_visual_fifo", terminal_visual_fifo);
    renderer_test_module.addImport("terminal_fonts", terminal_fonts);
    renderer_test_module.addImport("terminal_runtime", terminal_runtime);
    renderer_test_module.addImport("howl_vt", vt.module("howl_vt"));
    renderer_test_module.addImport("config", config);
    renderer_test_module.addImport("session_chrome_adapter", session_chrome_adapter);
    renderer_test_module.addImport("session_domain", session_domain);
    renderer_test_module.addImport("input_actions", input_actions);
    renderer_test_module.addImport("howl_render", render.module("howl_render"));
    renderer_test_module.addImport("howl_vk", vk.module("howl_vk"));
    renderer_test_module.addImport("howl_wayland", wayland.module("howl_wayland"));
    renderer_test_module.addImport("renderer_c", renderer_translate.createModule());
    renderer_test_module.addIncludePath(.{ .cwd_relative = "/usr/include/libdrm" });
    renderer_test_module.linkSystemLibrary("vulkan", .{});
    renderer_test_module.linkSystemLibrary("drm", .{});
    const renderer_tests = b.addTest(.{
        .root_module = renderer_test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    test_step.dependOn(&b.addRunArtifact(renderer_tests).step);
    const session_chrome_adapter_tests = b.addTest(.{ .root_module = session_chrome_adapter, .use_llvm = false, .use_lld = false });
    const run_session_chrome_adapter_tests = b.addRunArtifact(session_chrome_adapter_tests);
    test_step.dependOn(&run_session_chrome_adapter_tests.step);
    const chrome_equivalence_module = b.createModule(.{
        .root_source_file = b.path("test/chrome_state_equivalence_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    chrome_equivalence_module.addImport("session_chrome_adapter", session_chrome_adapter);
    chrome_equivalence_module.addImport("session_domain", session_domain);
    chrome_equivalence_module.addImport("howl_render", render.module("howl_render"));
    const chrome_equivalence_tests = b.addTest(.{
        .root_module = chrome_equivalence_module,
        .use_llvm = false,
        .use_lld = false,
    });
    test_step.dependOn(&b.addRunArtifact(chrome_equivalence_tests).step);
    const session_tests = b.addTest(.{ .root_module = session_domain, .use_llvm = false, .use_lld = false });
    test_step.dependOn(&b.addRunArtifact(session_tests).step);
    const input_action_tests = b.addTest(.{ .root_module = input_actions, .use_llvm = false, .use_lld = false });
    test_step.dependOn(&b.addRunArtifact(input_action_tests).step);
    const handoff_tests = b.addTest(.{
        .root_module = terminal_handoff,
        .use_llvm = false,
        .use_lld = false,
    });
    const run_handoff_tests = b.addRunArtifact(handoff_tests);
    test_step.dependOn(&run_handoff_tests.step);
    b.step("test-handoff", "Run terminal lifecycle handoff proofs")
        .dependOn(&run_handoff_tests.step);
    const visual_fifo_tests = b.addTest(.{
        .root_module = terminal_visual_fifo,
        .use_llvm = false,
        .use_lld = false,
    });
    const run_visual_fifo_tests = b.addRunArtifact(visual_fifo_tests);
    test_step.dependOn(&run_visual_fifo_tests.step);
    b.step("test-visual-fifo", "Run terminal visual FIFO proofs")
        .dependOn(&run_visual_fifo_tests.step);
    const terminal_runtime_tests = b.addTest(.{
        .root_module = terminal_runtime,
        .use_llvm = false,
        .use_lld = false,
    });
    test_step.dependOn(&b.addRunArtifact(terminal_runtime_tests).step);
    b.default_step = check;
}
