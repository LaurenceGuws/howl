//! Composes tests, simulations, benchmarks, and native hosts for root development.

const std = @import("std");

pub fn add(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vt: *std.Build.Module,
    text: *std.Build.Module,
    pty: *std.Build.Module,
    headless: *std.Build.Module,
) void {
    const check = b.step("check", "Compile every active Howl component and proof");
    const test_step = b.step("test", "Run every active Howl correctness proof");
    const audit = b.addSystemCommand(&.{"bash"});
    audit.addFileArg(b.path("tools/audit_source.sh"));
    check.dependOn(&audit.step);
    addVt(b, target, optimize, vt, check, test_step);
    addText(b, target, optimize, check, test_step);
    addPty(b, pty, check, test_step);
    addHeadless(b, target, optimize, headless, check, test_step);
    addHost(b, target, optimize, vt, text, check, test_step);
    b.default_step = check;
}

fn addVt(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vt: *std.Build.Module,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const unit = b.createModule(.{
        .root_source_file = b.path("howl-vt/test_unit.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const embedding = b.createModule(.{
        .root_source_file = b.path("howl-vt/test/native_embedding.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    embedding.addImport("howl_vt", vt);
    const fuzz = b.createModule(.{
        .root_source_file = b.path("howl-vt/test/fuzz_terminal.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    fuzz.addImport("howl_vt", vt);

    const unit_tests = addTest(b, "howl-vt-unit", unit);
    const embedding_tests = addTest(b, "howl-vt-embedding", embedding);
    const fuzz_tests = b.addTest(.{
        .name = "howl-vt-fuzz",
        .root_module = fuzz,
        .test_runner = .{
            .path = b.path("howl-vt/vendor/zig-0.16-test-runner/test_runner.zig"),
            .mode = .server,
        },
    });
    fuzz_tests.use_llvm = true;
    check.dependOn(&unit_tests.step);
    check.dependOn(&embedding_tests.step);
    check.dependOn(&fuzz_tests.step);
    test_step.dependOn(&addTestRun(b, unit_tests).step);
    test_step.dependOn(&addTestRun(b, embedding_tests).step);
    test_step.dependOn(&addTestRun(b, fuzz_tests).step);

    const fuzz_step = b.step("fuzz:terminal", "Fuzz the native Terminal ownership boundary");
    fuzz_step.dependOn(&addTestRun(b, fuzz_tests).step);

    const simulation = b.addExecutable(.{
        .name = "howl-vt-simulate",
        .root_module = b.createModule(.{
            .root_source_file = b.path("howl-vt/simulation_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    simulation.use_llvm = true;
    const run_simulation = b.addRunArtifact(simulation);
    if (b.args) |arguments| run_simulation.addArgs(arguments);
    b.step("simulate", "Run VT protocol and scrollback simulations").dependOn(&run_simulation.step);
    check.dependOn(&simulation.step);

    const benchmark = b.addExecutable(.{
        .name = "howl-vt-m7-baseline",
        .root_module = b.createModule(.{
            .root_source_file = b.path("howl-vt/benchmark_m7_baseline.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
    });
    const run_benchmark = b.addRunArtifact(benchmark);
    if (b.args) |arguments| run_benchmark.addArgs(arguments);
    b.step("benchmark:m7", "Run the m7 VT benchmark").dependOn(&run_benchmark.step);
}

fn addText(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const options = b.addOptions();
    options.addOption([]const u8, "primary_font", b.pathFromRoot("howl-text/testdata/primary.ttf"));
    options.addOption([]const u8, "symbol_font", b.pathFromRoot("howl-text/testdata/symbols.ttf"));
    options.addOption([]const u8, "mono_font", b.pathFromRoot("howl-text/testdata/mono.bdf"));
    const module = b.createModule(.{
        .root_source_file = b.path("howl-text/src/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.linkSystemLibrary("freetype", .{});
    module.linkSystemLibrary("harfbuzz", .{});
    module.addImport("test_fonts", options.createModule());
    const tests = addTest(b, "howl-text", module);
    check.dependOn(&tests.step);
    test_step.dependOn(&addTestRun(b, tests).step);
}

fn addPty(
    b: *std.Build,
    pty: *std.Build.Module,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const tests = addTest(b, "howl-pty", pty);
    check.dependOn(&tests.step);
    test_step.dependOn(&addTestRun(b, tests).step);
}

fn addHeadless(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    headless: *std.Build.Module,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const tests_module = b.createModule(.{
        .root_source_file = b.path("howl-headless/src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests_module.addImport("howl_headless", headless);
    const executable_module = b.createModule(.{
        .root_source_file = b.path("howl-headless/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    executable_module.addImport("howl_headless", headless);
    const executable = b.addExecutable(.{ .name = "howl-headless", .root_module = executable_module });
    executable.use_llvm = true;
    const api = addTest(b, "howl-headless-api", headless);
    const tests = addTest(b, "howl-headless", tests_module);
    check.dependOn(&api.step);
    check.dependOn(&executable.step);
    check.dependOn(&tests.step);
    test_step.dependOn(&addTestRun(b, api).step);
    test_step.dependOn(&addTestRun(b, tests).step);
    b.installArtifact(executable);
    const run = b.addRunArtifact(executable);
    if (b.args) |arguments| run.addArgs(arguments);
    b.step("run:headless", "Run the headless terminal emulator").dependOn(&run.step);
}

fn addHost(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vt: *std.Build.Module,
    text: *std.Build.Module,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const module = b.addModule("howl_host", .{
        .root_source_file = b.path("howl-host/src/howl_host.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addHostImports(b, module, vt, text);
    const api = addTest(b, "howl-host-api", module);

    const paths = b.addOptions();
    paths.addOption([]const u8, "font", b.pathFromRoot("howl-text/testdata/primary.ttf"));
    const tests_module = b.createModule(.{
        .root_source_file = b.path("howl-host/src/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addHostImports(b, tests_module, vt, text);
    tests_module.addImport("host_test_paths", paths.createModule());
    const tests = addTest(b, "howl-host", tests_module);

    const executable_module = b.createModule(.{
        .root_source_file = b.path("howl-host/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addHostImports(b, executable_module, vt, text);
    const executable = b.addExecutable(.{ .name = "howl-host", .root_module = executable_module });
    executable.use_llvm = true;
    check.dependOn(&api.step);
    check.dependOn(&tests.step);
    check.dependOn(&executable.step);
    test_step.dependOn(&addTestRun(b, tests).step);
    b.installArtifact(executable);
    const run = b.addRunArtifact(executable);
    if (b.args) |arguments| run.addArgs(arguments);
    b.step("run:host", "Run the native Wayland host").dependOn(&run.step);
}

fn addHostImports(
    b: *std.Build,
    module: *std.Build.Module,
    vt: *std.Build.Module,
    text: *std.Build.Module,
) void {
    module.addImport("howl_vt", vt);
    module.addImport("howl_text", text);
    module.addIncludePath(b.path("howl-host/vendor/xdg-shell"));
    module.addCSourceFile(.{
        .file = b.path("howl-host/vendor/xdg-shell/xdg-shell-protocol.c"),
        .flags = &.{"-std=c11"},
    });
    inline for (.{
        "wayland-client",
        "wayland-egl",
        "EGL",
        "GLESv2",
        "xkbcommon",
        "freetype",
        "harfbuzz",
    }) |library| module.linkSystemLibrary(library, .{});
}

fn addTest(b: *std.Build, name: []const u8, module: *std.Build.Module) *std.Build.Step.Compile {
    const tests = b.addTest(.{ .name = name, .root_module = module, .filters = b.args orelse &.{} });
    tests.use_llvm = true;
    return tests;
}

fn addTestRun(b: *std.Build, tests: *std.Build.Step.Compile) *std.Build.Step.Run {
    const run = b.addRunArtifact(tests);
    if (b.args != null) run.has_side_effects = true;
    return run;
}
