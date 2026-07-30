const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("howl_vt", .{
        .root_source_file = b.path("src/howl_vt.zig"),
        .target = target,
        .optimize = optimize,
    });
    const check = b.step("check", "Compile the VT module and every owned proof");
    const test_step = b.step("test", "Run every owned VT proof");

    const unicode_digest_module = b.createModule(.{
        .root_source_file = b.path("src/unicode_17_digest.zig"),
        .target = target,
        .optimize = optimize,
    });
    const unicode_digest = b.addExecutable(.{
        .name = "howl-vt-check-unicode-17",
        .root_module = unicode_digest_module,
        .use_llvm = false,
        .use_lld = false,
    });
    const run_unicode_digest = b.addRunArtifact(unicode_digest);
    check.dependOn(&run_unicode_digest.step);
    test_step.dependOn(&run_unicode_digest.step);

    const unit_module = b.createModule(.{
        .root_source_file = b.path("test_unit.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    const unit = b.addTest(.{
        .name = "howl-vt-unit",
        .root_module = unit_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&unit.step);
    const run_unit = b.addRunArtifact(unit);
    run_unit.addPassthruArgs();
    test_step.dependOn(&run_unit.step);

    const embedding_module = b.createModule(.{
        .root_source_file = b.path("test/native_embedding.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    embedding_module.addImport("howl_vt", module);
    const embedding = b.addTest(.{
        .name = "howl-vt-embedding",
        .root_module = embedding_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&embedding.step);
    const run_embedding = b.addRunArtifact(embedding);
    run_embedding.addPassthruArgs();
    test_step.dependOn(&run_embedding.step);

    const fuzz_module = b.createModule(.{
        .root_source_file = b.path("test/fuzz_terminal.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    fuzz_module.addImport("howl_vt", module);
    const fuzz = b.addTest(.{
        .name = "howl-vt-fuzz",
        .root_module = fuzz_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&fuzz.step);
    const run_fuzz = b.addRunArtifact(fuzz);
    run_fuzz.addPassthruArgs();
    test_step.dependOn(&run_fuzz.step);
    b.step("fuzz", "Fuzz the native Terminal ownership boundary").dependOn(&run_fuzz.step);

    const simulation_module = b.createModule(.{
        .root_source_file = b.path("simulation_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const simulation = b.addExecutable(.{
        .name = "howl-vt-simulate",
        .root_module = simulation_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&simulation.step);
    const run_simulation = b.addRunArtifact(simulation);
    run_simulation.addPassthruArgs();
    b.step("simulate", "Run VT protocol and scrollback simulations").dependOn(&run_simulation.step);

    const benchmark_module = b.createModule(.{
        .root_source_file = b.path("benchmark_m7_baseline.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });
    const benchmark = b.addExecutable(.{
        .name = "howl-vt-m7-baseline",
        .root_module = benchmark_module,
        .use_llvm = false,
        .use_lld = false,
    });
    const run_benchmark = b.addRunArtifact(benchmark);
    run_benchmark.addPassthruArgs();
    b.step("benchmark", "Run the m7 VT benchmark").dependOn(&run_benchmark.step);

    b.default_step = check;
}
