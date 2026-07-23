const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const control = b.dependency("howl_control", .{ .target = target, .optimize = optimize });
    const render = b.dependency("howl_render", .{
        .target = target,
        .optimize = optimize,
        .terminal = true,
        .native_text = true,
        .generated_glyphs = true,
    });
    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_control", control.module("howl_control"));
    module.addImport("howl_render", render.module("howl_render"));
    configureNative(b, module);

    const executable = b.addExecutable(.{ .name = "howl-host", .root_module = module });
    executable.use_llvm = true;
    b.installArtifact(executable);

    const tests = b.addTest(.{
        .name = "howl-host",
        .root_module = testModule(b, target, optimize, control, render),
        .filters = b.args orelse &.{},
    });
    tests.use_llvm = true;
    const check = b.step("check", "Compile the control-backed host and proofs");
    check.dependOn(&executable.step);
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    if (b.args != null) run_tests.has_side_effects = true;
    const test_step = b.step("test", "Run the control-backed host proofs");
    test_step.dependOn(&run_tests.step);

    const run = b.addRunArtifact(executable);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |arguments| run.addArgs(arguments);
    b.step("run", "Run the control-backed host").dependOn(&run.step);
    b.default_step = b.getInstallStep();
}

fn testModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    control: *std.Build.Dependency,
    render: *std.Build.Dependency,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_control", control.module("howl_control"));
    module.addImport("howl_render", render.module("howl_render"));
    configureNative(b, module);
    return module;
}

fn configureNative(b: *std.Build, module: *std.Build.Module) void {
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

fn configureDevice(module: *std.Build.Module) void {
    module.link_libc = true;
    module.linkSystemLibrary("wayland-egl", .{});
    module.linkSystemLibrary("EGL", .{});
    module.linkSystemLibrary("GLESv2", .{});
    module.linkSystemLibrary("xkbcommon", .{});
}
