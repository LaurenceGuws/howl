const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // Other terminal consumers must share VT's exact OSC 52 validation grammar.
    // Export only this pure leaf; canonical VT never acquires a client dependency.
    const clipboard_grammar = b.addModule("vt_clipboard_grammar", .{
        .root_source_file = b.path("src/clipboard_grammar.zig"),
        .target = target,
        .optimize = optimize,
    });
    const module = b.addModule("howl_vt", .{
        .root_source_file = b.path("src/howl_vt.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("vt_clipboard_grammar", clipboard_grammar);
    const native_types = b.addTranslateC(.{ .root_source_file = b.path("include/howl_vt_native.h"), .target = target, .optimize = optimize });
    const native = b.addModule("howl_vt_native", .{ .root_source_file = b.path("src/native.zig"), .target = target, .optimize = optimize });
    native.addImport("howl_vt", module);
    native.addImport("vt_native_types", native_types.createModule());
    b.addNamedLazyPath("howl_vt_native_header", b.path("include/howl_vt_native.h"));
    const abi_root = b.createModule(.{
        .root_source_file = b.path("src/abi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    abi_root.addImport("howl_vt_native", native);
    const abi = b.addLibrary(.{ .name = "howl_vt_native", .linkage = .static, .root_module = abi_root, .use_llvm = false, .use_lld = false });
    abi.installHeader(b.path("include/howl_vt_native.h"), "howl_vt_native.h");
    b.installArtifact(abi);
    // Optional language-binding proof; ordinary Zig VT builds need no Dart SDK.
    const dart_probe_root = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    dart_probe_root.addCSourceFile(.{ .file = b.path("test/native_dart_record.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
    dart_probe_root.addIncludePath(b.path("include"));
    const dart_probe = b.addExecutable(.{ .name = "howl-vt-dart-record", .root_module = dart_probe_root, .use_llvm = false, .use_lld = false });
    const dart_proof = b.addSystemCommand(&.{ "dart", "run" });
    dart_proof.addFileArg(b.path("test/native_dart.dart"));
    dart_proof.addArtifactArg(dart_probe);
    dart_proof.setCwd(b.path("."));
    b.step("test:dart-native", "Qualify the owned Dart binding against an actual C record").dependOn(&dart_proof.step);
    const check = b.step("check", "Compile the VT module and every owned proof");
    check.dependOn(&dart_probe.step);
    check.dependOn(&abi.step);
    const audit = b.step("audit", "Audit every owned Zig source file");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    check.dependOn(audit);
    const test_step = b.step("test", "Run every owned VT proof");

    const foreign_root = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    foreign_root.linkLibrary(abi);
    foreign_root.addCSourceFile(.{ .file = b.path("test/native_client.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
    foreign_root.addCSourceFile(.{ .file = b.path("test/header.cpp"), .flags = &.{ "-std=c++17", "-Wall", "-Wextra", "-Werror" } });
    const foreign = b.addExecutable(.{ .name = "howl-vt-foreign", .root_module = foreign_root, .use_llvm = false, .use_lld = false });
    check.dependOn(&foreign.step);
    const foreign_run = b.addRunArtifact(foreign);
    test_step.dependOn(&foreign_run.step);
    b.step("test:foreign", "Run the standalone C/C++ VT owner proof").dependOn(&foreign_run.step);

    const native_proofs = b.addTest(.{ .name = "howl-vt-native-contract", .root_module = native, .use_llvm = false, .use_lld = false });
    check.dependOn(&native_proofs.step);
    const native_run = b.addRunArtifact(native_proofs);
    test_step.dependOn(&native_run.step);
    const native_step = b.step("test:native", "Run the VT-owned native contract proofs");
    native_step.dependOn(&native_run.step);
    const owner_root = b.createModule(.{ .root_source_file = b.path("test/native_owner.zig"), .target = target, .optimize = optimize });
    owner_root.addImport("howl_vt_native", native);
    const owner_tests = b.addTest(.{ .name = "howl-vt-native-owner", .root_module = owner_root, .use_llvm = false, .use_lld = false });
    check.dependOn(&owner_tests.step);
    const owner_run = b.addRunArtifact(owner_tests);
    test_step.dependOn(&owner_run.step);
    native_step.dependOn(&owner_run.step);

    const output_root = b.createModule(.{ .root_source_file = b.path("test/native_output.zig"), .target = target, .optimize = optimize });
    output_root.addImport("howl_vt_native", native);
    const output_tests = b.addTest(.{ .name = "howl-vt-native-output", .root_module = output_root, .use_llvm = false, .use_lld = false });
    check.dependOn(&output_tests.step);
    const output_run = b.addRunArtifact(output_tests);
    test_step.dependOn(&output_run.step);
    native_step.dependOn(&output_run.step);
    b.step("test:output", "Qualify immutable logical-output results and allocation transfer").dependOn(&output_run.step);

    const observation_root = b.createModule(.{ .root_source_file = b.path("test/native_observation.zig"), .target = target, .optimize = optimize });
    observation_root.addImport("howl_vt_native", native);
    const observation_tests = b.addTest(.{ .name = "howl-vt-native-observation", .root_module = observation_root, .use_llvm = false, .use_lld = false });
    check.dependOn(&observation_tests.step);
    const observation_run = b.addRunArtifact(observation_tests);
    test_step.dependOn(&observation_run.step);
    native_step.dependOn(&observation_run.step);

    // Optional observation encoding is never imported by the live VT root.
    const codec = b.addModule("howl_vt_codec", .{
        .root_source_file = b.path("src/codec.zig"),
        .target = target,
        .optimize = optimize,
    });
    codec.addImport("vt_clipboard_grammar", clipboard_grammar);
    const grammar_proofs = b.addTest(.{ .name = "howl-vt-clipboard-grammar", .root_module = clipboard_grammar, .use_llvm = false, .use_lld = false });
    check.dependOn(&grammar_proofs.step);
    test_step.dependOn(&b.addRunArtifact(grammar_proofs).step);
    const codec_proofs = b.addTest(.{
        .name = "howl-vt-codec",
        .root_module = codec,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&codec_proofs.step);
    test_step.dependOn(&b.addRunArtifact(codec_proofs).step);

    const encoder_root = b.createModule(.{
        .root_source_file = b.path("test/codec_encoder.zig"),
        .target = target,
        .optimize = optimize,
    });
    encoder_root.addImport("howl_vt", module);
    encoder_root.addImport("howl_vt_codec", codec);
    const encoder_proofs = b.addTest(.{
        .name = "howl-vt-codec-encoder",
        .root_module = encoder_root,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&encoder_proofs.step);
    test_step.dependOn(&b.addRunArtifact(encoder_proofs).step);

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
    unit_module.addImport("vt_clipboard_grammar", clipboard_grammar);
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
    b.step("test:terminal", "Run canonical VT unit proofs").dependOn(&run_unit.step);

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
    simulation_module.addImport("vt_clipboard_grammar", clipboard_grammar);
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
    test_step.dependOn(&run_simulation.step);

    const benchmark_module = b.createModule(.{
        .root_source_file = b.path("benchmark/terminal_benchmark.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .link_libc = true,
    });
    benchmark_module.addImport("howl_vt", module);
    const benchmark = b.addExecutable(.{
        .name = "howl-vt-benchmark",
        .root_module = benchmark_module,
        .use_llvm = false,
        .use_lld = false,
    });
    const run_benchmark = b.addRunArtifact(benchmark);
    run_benchmark.addPassthruArgs();
    b.step("benchmark", "Run the VT benchmark").dependOn(&run_benchmark.step);

    b.default_step = check;
}
