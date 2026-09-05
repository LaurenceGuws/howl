//! Full shared terminal-renderer WebAssembly canary.
const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize: std.builtin.OptimizeMode = .ReleaseSafe;
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .wasi,
        .cpu_features_add = std.Target.wasm.featureSet(&.{.exception_handling}),
    });
    const client = b.dependency("howl_client", .{ .target = target, .optimize = optimize });
    const render = b.dependency("howl_render", .{
        .target = target,
        .optimize = optimize,
        .native_text = true,
        .generated_glyphs = false,
        .bundled_text = true,
    });
    const text = b.dependency("howl_text", .{
        .target = target,
        .optimize = optimize,
        .bundled = true,
    });
    const root = b.createModule(.{
        .root_source_file = b.path("probe.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
        .strip = true,
    });
    root.addImport("howl_client", client.module("howl_client"));
    root.addImport("howl_render", render.module("howl_render"));
    root.export_symbol_names = &.{
        "font_ptr",   "font_capacity", "run",       "report_ptr", "report_len",
        "pixels_ptr", "pixels_len",    "error_ptr", "error_len",
    };
    const wasm = b.addExecutable(.{ .name = "howl-render-proof", .root_module = root });
    wasm.entry = .disabled;
    wasm.export_memory = true;
    wasm.initial_memory = 96 * 1024 * 1024;
    wasm.max_memory = 128 * 1024 * 1024;
    wasm.wasi_exec_model = .reactor;

    const check = b.step("check", "Run shared terminal renderer in Wasm on one bounded semantic view");
    const run = b.addSystemCommand(&.{ "node", "tests/check.mjs" });
    run.setCwd(b.path("."));
    run.addFileArg(wasm.getEmittedBin());
    run.addFileArg(text.path("testdata/primary.ttf"));
    check.dependOn(&run.step);
    b.default_step = check;
}
