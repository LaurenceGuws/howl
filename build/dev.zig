//! Composes tests, simulations, benchmarks, and native hosts for root development.

const std = @import("std");

pub fn add(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vt: *std.Build.Module,
    text: *std.Build.Module,
    frame: *std.Build.Module,
    render: *std.Build.Module,
    pty: *std.Build.Module,
    control: *std.Build.Module,
) void {
    const probe_enabled = b.createModule(.{
        .root_source_file = b.path("tools/probe.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const probe_disabled = b.createModule(.{
        .root_source_file = b.path("tools/probe_noop.zig"),
        .target = target,
        .optimize = optimize,
    });
    const check = b.step("check", "Compile every active Howl component and proof");
    const test_step = b.step("test", "Run every active Howl correctness proof");
    const audit = b.addSystemCommand(&.{"bash"});
    audit.addFileArg(b.path("tools/audit_source.sh"));
    check.dependOn(&audit.step);
    const protocol = b.addSystemCommand(&.{
        "nu",
        "-c",
        "source protocol_coverage.nu; protocol validate --fail | ignore",
    });
    check.dependOn(&protocol.step);
    addVt(b, target, optimize, vt, check, test_step);
    addText(b, target, optimize, check, test_step);
    addFrame(b, frame, check, test_step);
    addRender(b, render, check, test_step);
    addWindow(
        b,
        target,
        optimize,
        vt,
        text,
        frame,
        render,
        control,
        probe_disabled,
        probe_enabled,
        check,
        test_step,
    );
    addPty(b, pty, check, test_step);
    addControl(b, target, optimize, control, check, test_step);
    addProbe(
        b,
        target,
        optimize,
        vt,
        frame,
        render,
        pty,
        probe_disabled,
        probe_enabled,
        check,
        test_step,
    );
    b.default_step = check;
}

fn addProbe(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vt: *std.Build.Module,
    frame: *std.Build.Module,
    render: *std.Build.Module,
    pty: *std.Build.Module,
    disabled: *std.Build.Module,
    enabled: *std.Build.Module,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const enabled_tests = addTest(b, "howl-probe", enabled);
    const disabled_tests = addTest(b, "howl-probe-disabled", disabled);
    check.dependOn(&enabled_tests.step);
    check.dependOn(&disabled_tests.step);
    test_step.dependOn(&addTestRun(b, enabled_tests).step);
    test_step.dependOn(&addTestRun(b, disabled_tests).step);

    const paths = b.addOptions();
    paths.addOption([]const u8, "font", b.pathFromRoot("howl-text/testdata/primary.ttf"));
    paths.addOption(bool, "probe_scenario", true);
    const enabled_scenario = probeScenario(
        b,
        "howl-probe-scenario",
        target,
        optimize,
        vt,
        frame,
        render,
        pty,
        enabled,
        paths.createModule(),
    );
    const disabled_scenario = probeScenario(
        b,
        "howl-probe-noop-scenario",
        target,
        optimize,
        vt,
        frame,
        render,
        pty,
        disabled,
        paths.createModule(),
    );
    check.dependOn(&enabled_scenario.step);
    check.dependOn(&disabled_scenario.step);

    const run_enabled = b.addRunArtifact(enabled_scenario);
    run_enabled.addArg(b.pathFromRoot("howl-probe.jsonl"));
    b.step("measure:probe", "Measure the deterministic PTY-to-render pipeline").dependOn(&run_enabled.step);
    const run_disabled = b.addRunArtifact(disabled_scenario);
    b.step("measure:probe-disabled", "Measure the compile-time disabled probe boundary").dependOn(&run_disabled.step);
}

fn probeScenario(
    b: *std.Build,
    name: []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vt: *std.Build.Module,
    frame: *std.Build.Module,
    render: *std.Build.Module,
    pty: *std.Build.Module,
    probe: *std.Build.Module,
    paths: *std.Build.Module,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path("tools/probe_scenario.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addImport("howl_probe", probe);
    module.addImport("howl_vt", vt);
    module.addImport("howl_frame", frame);
    module.addImport("howl_render", render);
    module.addImport("howl_pty", pty);
    module.addImport("probe_paths", paths);
    const executable = b.addExecutable(.{ .name = name, .root_module = module });
    executable.use_llvm = true;
    return executable;
}

fn addWindow(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    vt: *std.Build.Module,
    text: *std.Build.Module,
    frame: *std.Build.Module,
    render: *std.Build.Module,
    control: *std.Build.Module,
    probe_disabled: *std.Build.Module,
    probe_enabled: *std.Build.Module,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const workspace = b.createModule(.{
        .root_source_file = b.path("howl-window/src/workspace.zig"),
        .target = target,
        .optimize = optimize,
    });
    const workspace_tests = addTest(b, "howl-window-workspace", workspace);
    check.dependOn(&workspace_tests.step);
    test_step.dependOn(&addTestRun(b, workspace_tests).step);

    const module = b.createModule(.{
        .root_source_file = b.path("howl-window/src/window.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addWindowImports(b, module, vt, text, frame, render, control, probe_disabled);
    const tests = addTest(b, "howl-window", module);
    check.dependOn(&tests.step);
    test_step.dependOn(&addTestRun(b, tests).step);

    const executable_module = b.createModule(.{
        .root_source_file = b.path("howl-window/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addWindowImports(b, executable_module, vt, text, frame, render, control, probe_disabled);
    const executable = b.addExecutable(.{ .name = "howl-window", .root_module = executable_module });
    executable.use_llvm = true;
    check.dependOn(&executable.step);
    b.installArtifact(executable);
    const run = b.addRunArtifact(executable);
    if (b.args) |arguments| run.addArgs(arguments);
    b.step("run:window", "Run the native Wayland window").dependOn(&run.step);

    const probe_module = b.createModule(.{
        .root_source_file = b.path("howl-window/src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    addWindowImports(b, probe_module, vt, text, frame, render, control, probe_enabled);
    const probe_executable = b.addExecutable(.{ .name = "howl-window-probe", .root_module = probe_module });
    probe_executable.use_llvm = true;
    check.dependOn(&probe_executable.step);
    const run_probe = b.addRunArtifact(probe_executable);
    if (b.args) |arguments| run_probe.addArgs(arguments);
    b.step("run:window-probe", "Run the native window with bounded development probes").dependOn(&run_probe.step);
}

fn addWindowImports(
    b: *std.Build,
    module: *std.Build.Module,
    vt: *std.Build.Module,
    text: *std.Build.Module,
    frame: *std.Build.Module,
    render: *std.Build.Module,
    control: *std.Build.Module,
    probe: *std.Build.Module,
) void {
    module.addImport("howl_vt", vt);
    module.addImport("howl_text", text);
    module.addImport("howl_frame", frame);
    module.addImport("howl_render", render);
    module.addImport("howl_control", control);
    module.addImport("howl_probe", probe);
    module.addIncludePath(b.path("howl-window/vendor/xdg-shell"));
    module.addCSourceFile(.{
        .file = b.path("howl-window/vendor/xdg-shell/xdg-shell-protocol.c"),
        .flags = &.{"-std=c11"},
    });
    inline for (.{ "wayland-client", "wayland-egl", "EGL", "GLESv2", "xkbcommon" }) |library|
        module.linkSystemLibrary(library, .{});
}

fn addRender(
    b: *std.Build,
    render: *std.Build.Module,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const paths = b.addOptions();
    paths.addOption([]const u8, "font", b.pathFromRoot("howl-text/testdata/primary.ttf"));
    render.addImport("render_test_paths", paths.createModule());
    const tests = addTest(b, "howl-render", render);
    check.dependOn(&tests.step);
    test_step.dependOn(&addTestRun(b, tests).step);
}

fn addFrame(
    b: *std.Build,
    frame: *std.Build.Module,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const tests = addTest(b, "howl-frame", frame);
    check.dependOn(&tests.step);
    test_step.dependOn(&addTestRun(b, tests).step);
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

fn addControl(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    control: *std.Build.Module,
    check: *std.Build.Step,
    test_step: *std.Build.Step,
) void {
    const tests_module = b.createModule(.{
        .root_source_file = b.path("howl-control/src/test.zig"),
        .target = target,
        .optimize = optimize,
    });
    tests_module.addImport("howl_control", control);
    const api = addTest(b, "howl-control-api", control);
    const tests = addTest(b, "howl-control", tests_module);
    check.dependOn(&api.step);
    check.dependOn(&tests.step);
    test_step.dependOn(&addTestRun(b, api).step);
    test_step.dependOn(&addTestRun(b, tests).step);
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
