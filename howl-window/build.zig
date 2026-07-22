const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const vt = b.dependency("howl_vt", .{ .target = target, .optimize = optimize });
    const text = b.dependency("howl_text", .{ .target = target, .optimize = optimize });
    const frame = b.dependency("howl_frame", .{ .target = target, .optimize = optimize });
    const render = b.dependency("howl_render", .{ .target = target, .optimize = optimize });
    const pty = b.dependency("howl_pty", .{ .target = target, .optimize = optimize });
    const control = b.dependency("howl_control", .{ .target = target, .optimize = optimize });
    const probe_enabled = b.option(bool, "probe", "Enable temporary development measurements") orelse false;
    const disabled_probe = b.createModule(.{
        .root_source_file = b.path("build/probe_disabled.zig"),
        .target = target,
        .optimize = optimize,
    });
    const enabled_probe = b.createModule(.{
        .root_source_file = b.path("build/probe_enabled.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const probe = if (probe_enabled) enabled_probe else disabled_probe;
    const dependencies = Dependencies{
        .vt = vt.module("howl_vt"),
        .text = text.module("howl_text"),
        .frame = frame.module("howl_frame"),
        .render = render.module("howl_render"),
        .control = control.module("howl_control"),
        .probe = probe,
    };

    const module = b.createModule(.{
        .root_source_file = b.path("src/window.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureWindowModule(b, module, dependencies);
    const window_tests = b.addTest(.{ .name = "howl-window", .root_module = module, .filters = b.args orelse &.{} });
    window_tests.use_llvm = true;
    const workspace_module = b.createModule(.{
        .root_source_file = b.path("src/workspace.zig"),
        .target = target,
        .optimize = optimize,
    });
    const workspace_tests = b.addTest(.{
        .name = "howl-window-workspace",
        .root_module = workspace_module,
        .filters = b.args orelse &.{},
    });
    workspace_tests.use_llvm = true;

    const executable_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    configureWindowModule(b, executable_module, dependencies);
    const executable = b.addExecutable(.{ .name = "howl-window", .root_module = executable_module });
    executable.use_llvm = true;
    b.installArtifact(executable);
    const check = b.step("check", "Compile the native window, workspace, and owned proofs");
    check.dependOn(&window_tests.step);
    check.dependOn(&workspace_tests.step);
    check.dependOn(&executable.step);
    const run_window_tests = b.addRunArtifact(window_tests);
    const run_workspace_tests = b.addRunArtifact(workspace_tests);
    if (b.args != null) {
        run_window_tests.has_side_effects = true;
        run_workspace_tests.has_side_effects = true;
    }
    const test_step = b.step("test", "Run native window and workspace proofs");
    test_step.dependOn(&run_window_tests.step);
    test_step.dependOn(&run_workspace_tests.step);
    const run = b.addRunArtifact(executable);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |arguments| run.addArgs(arguments);
    b.step("run", "Run the native Wayland terminal").dependOn(&run.step);

    const probe_tests = b.addTest(.{ .name = "howl-window-probe", .root_module = enabled_probe });
    probe_tests.use_llvm = true;
    check.dependOn(&probe_tests.step);
    test_step.dependOn(&b.addRunArtifact(probe_tests).step);

    const paths = b.addOptions();
    paths.addOption([]const u8, "font", text.path("testdata/primary.ttf").getPath(b));
    paths.addOption(bool, "probe_scenario", true);
    const scenario = probeScenario(
        b,
        target,
        optimize,
        vt,
        frame,
        render,
        pty.module("howl_pty"),
        enabled_probe,
        paths.createModule(),
    );
    check.dependOn(&scenario.step);
    const measure = b.addRunArtifact(scenario);
    if (b.args) |arguments| measure.addArgs(arguments);
    b.step("measure", "Measure the deterministic PTY-to-render pipeline").dependOn(&measure.step);

    const disabled_scenario = probeScenario(
        b,
        target,
        optimize,
        vt,
        frame,
        render,
        pty.module("howl_pty"),
        disabled_probe,
        paths.createModule(),
    );
    check.dependOn(&disabled_scenario.step);
    const measure_disabled = b.addRunArtifact(disabled_scenario);
    if (b.args) |arguments| measure_disabled.addArgs(arguments);
    b.step("measure-disabled", "Measure the compile-time disabled probe boundary").dependOn(&measure_disabled.step);
    b.default_step = b.getInstallStep();
}

fn probeScenario(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vt: *std.Build.Dependency,
    frame: *std.Build.Dependency,
    render: *std.Build.Dependency,
    pty: *std.Build.Module,
    probe: *std.Build.Module,
    paths: *std.Build.Module,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path("build/probe_scenario.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addImport("howl_probe", probe);
    module.addImport("howl_vt", vt.module("howl_vt"));
    module.addImport("howl_frame", frame.module("howl_frame"));
    module.addImport("howl_render", render.module("howl_render"));
    module.addImport("howl_pty", pty);
    module.addImport("probe_paths", paths);
    const executable = b.addExecutable(.{ .name = "howl-window-probe-scenario", .root_module = module });
    executable.use_llvm = true;
    return executable;
}

const Dependencies = struct {
    vt: *std.Build.Module,
    text: *std.Build.Module,
    frame: *std.Build.Module,
    render: *std.Build.Module,
    control: *std.Build.Module,
    probe: *std.Build.Module,
};

fn configureWindowModule(
    b: *std.Build,
    module: *std.Build.Module,
    dependencies: Dependencies,
) void {
    module.addImport("howl_vt", dependencies.vt);
    module.addImport("howl_text", dependencies.text);
    module.addImport("howl_frame", dependencies.frame);
    module.addImport("howl_render", dependencies.render);
    module.addImport("howl_control", dependencies.control);
    module.addImport("howl_probe", dependencies.probe);
    module.addIncludePath(b.path("vendor/xdg-shell"));
    module.addCSourceFile(.{
        .file = b.path("vendor/xdg-shell/xdg-shell-protocol.c"),
        .flags = &.{"-std=c11"},
    });
    inline for (.{ "wayland-client", "wayland-egl", "EGL", "GLESv2", "xkbcommon" }) |library|
        module.linkSystemLibrary(library, .{});
}
