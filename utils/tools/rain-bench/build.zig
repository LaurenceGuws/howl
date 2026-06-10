const std = @import("std");

const Build = std.Build;
const Compile = Build.Step.Compile;

const harness_install_dir: Build.InstallDir = .{ .custom = "harness" };

const Steps = struct {
    stress_rain: *Build.Step,
    stress_rain_build: *Build.Step,
    stress_rain_ascii: *Build.Step,
    stress_rain_ascii_build: *Build.Step,
    stress_rain_mixed: *Build.Step,
    stress_rain_mixed_build: *Build.Step,
    stress_rain_visual: *Build.Step,
    stress_rain_visual_build: *Build.Step,
};

pub fn build(b: *Build) void {
    const steps = createSteps(b);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const rain_stress = buildLibcExe(b, "ascii_rain_stress", "ascii_rain_stress.zig", target, optimize);
    const visual_rain_stress = buildLibcExe(b, "visual_rain_stress", "visual_rain_stress.zig", target, optimize);
    wireStressSteps(b, steps, rain_stress, visual_rain_stress);
}

fn createSteps(b: *Build) Steps {
    return .{
        .stress_rain = b.step("stress:rain", "Run hostile ASCII rain terminal traffic generator"),
        .stress_rain_build = b.step("stress:rain:build", "Build hostile ASCII rain terminal traffic generator"),
        .stress_rain_ascii = b.step("stress:rain:ascii", "Run pure ASCII rain stress generator with metrics"),
        .stress_rain_ascii_build = b.step("stress:rain:ascii:build", "Build pure ASCII rain stress generator with metrics defaults"),
        .stress_rain_mixed = b.step("stress:rain:mixed", "Run mixed glyph rain stress generator with metrics"),
        .stress_rain_mixed_build = b.step("stress:rain:mixed:build", "Build mixed glyph rain stress generator with metrics defaults"),
        .stress_rain_visual = b.step("stress:rain:visual", "Run visual ASCII rain correctness stress generator"),
        .stress_rain_visual_build = b.step("stress:rain:visual:build", "Build visual ASCII rain correctness stress generator"),
    };
}

fn wireStressSteps(b: *Build, steps: Steps, rain_stress: *Compile, visual_rain_stress: *Compile) void {
    stageHarnessArtifact(b, steps.stress_rain_build, rain_stress);
    stageHarnessArtifact(b, steps.stress_rain_ascii_build, rain_stress);
    stageHarnessArtifact(b, steps.stress_rain_mixed_build, rain_stress);
    stageHarnessArtifact(b, steps.stress_rain_visual_build, visual_rain_stress);

    const run_rain = b.addRunArtifact(rain_stress);
    if (b.args) |args| run_rain.addArgs(args);
    steps.stress_rain.dependOn(&run_rain.step);

    const run_rain_ascii = b.addRunArtifact(rain_stress);
    run_rain_ascii.addArgs(&.{ "--ascii", "--metrics", "--flush-every", "1" });
    steps.stress_rain_ascii.dependOn(&run_rain_ascii.step);

    const run_rain_mixed = b.addRunArtifact(rain_stress);
    run_rain_mixed.addArgs(&.{ "--mixed", "--metrics", "--flush-every", "1" });
    steps.stress_rain_mixed.dependOn(&run_rain_mixed.step);

    const run_visual = b.addRunArtifact(visual_rain_stress);
    if (b.args) |args| {
        run_visual.addArgs(args);
    } else {
        run_visual.addArgs(&.{"--metrics"});
    }
    steps.stress_rain_visual.dependOn(&run_visual.step);
}

fn stageHarnessArtifact(b: *Build, step: *Build.Step, exe: *Compile) void {
    step.dependOn(&b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = harness_install_dir },
        .dest_sub_path = exe.out_filename,
    }).step);
}

fn buildLibcExe(b: *Build, name: []const u8, path: []const u8, target: Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *Compile {
    const artifact_name = artifactName(b, name, optimize);
    const exe = b.addExecutable(.{
        .name = artifact_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.use_llvm = true;
    exe.root_module.link_libc = true;
    return exe;
}

fn artifactName(b: *Build, base: []const u8, optimize: std.builtin.OptimizeMode) []const u8 {
    return b.fmt("{s}_{s}", .{ base, optimizeSuffix(optimize) });
}

fn optimizeSuffix(optimize: std.builtin.OptimizeMode) []const u8 {
    return switch (optimize) {
        .Debug => "debug",
        .ReleaseSafe => "release_safe",
        .ReleaseFast => "release_fast",
        .ReleaseSmall => "release_small",
    };
}
