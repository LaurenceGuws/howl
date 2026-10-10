const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const renderer_enabled = b.option(
        bool,
        "renderer",
        "Build the terminal renderer module and its howl-text dependencies",
    ) orelse true;
    const bundled_text = b.option(
        bool,
        "bundled_text",
        "Build howl-text with its pinned target FreeType/HarfBuzz sources",
    ) orelse false;
    if (bundled_text and !renderer_enabled)
        std.process.fatal("bundled_text requires renderer", .{});

    // Always expose the small dependency-free limits contract. The Web wire
    // client uses this without constructing the terminal renderer or text stack.
    const limits = b.addModule("howl_render_limits", .{
        .root_source_file = b.path("src/limits.zig"),
        .target = target,
        .optimize = optimize,
    });

    const check = b.step("check", "Compile maintained howl-render proofs");
    const test_step = b.step("test", "Run maintained howl-render proofs");
    const audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    audit.setCwd(b.path("."));
    check.dependOn(&audit.step);

    if (!renderer_enabled) {
        // Freestanding consumers need a compile proof, not std's process-backed
        // test runner. The full renderer build below executes limits.zig tests.
        const limits_check = b.addObject(.{
            .name = "howl-render-limits-check",
            .root_module = limits,
            .use_llvm = false,
            .use_lld = false,
        });
        check.dependOn(&limits_check.step);
        test_step.dependOn(&limits_check.step);
        b.default_step = check;
        return;
    }

    const limits_tests = b.addTest(.{
        .name = "howl-render-limits",
        .root_module = limits,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&limits_tests.step);
    test_step.dependOn(&b.addRunArtifact(limits_tests).step);

    const root_source = b.path("src/root.zig");
    const module = b.addModule("howl_render", .{
        .root_source_file = root_source,
        .target = target,
        .optimize = optimize,
    });
    const test_module = b.createModule(.{
        .root_source_file = root_source,
        .target = target,
        .optimize = optimize,
    });
    module.addImport("limits", limits);
    test_module.addImport("limits", limits);

    const vt = b.dependency("howl_vt", .{
        .target = target,
        .optimize = optimize,
    }).module("howl_vt");
    const text = b.dependency("howl_text", .{
        .target = target,
        .optimize = optimize,
        .bundled = bundled_text,
    }).module("howl_text");
    const cache_module = b.createModule(.{ .root_source_file = b.path("src/glyph_cache.zig"), .target = target, .optimize = optimize });
    cache_module.addImport("howl_text", text);
    const cache_tests = b.addTest(.{ .name = "howl-render-cache", .root_module = cache_module, .use_llvm = false, .use_lld = false });
    check.dependOn(&cache_tests.step);
    test_step.dependOn(&b.addRunArtifact(cache_tests).step);

    module.addImport("howl_text", text);
    test_module.addImport("howl_text", text);

    const source_semantics = b.createModule(.{
        .root_source_file = b.path("src/source.zig"),
        .target = target,
        .optimize = optimize,
    });
    const renderer = rendererModule(
        b,
        target,
        optimize,
        limits,
        source_semantics,
        text,
    );
    const cursor_tests = b.addTest(.{
        .name = "howl-render-cursor",
        .root_module = renderer,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&cursor_tests.step);
    test_step.dependOn(&b.addRunArtifact(cursor_tests).step);
    const adapter = adapterModule(
        b,
        target,
        optimize,
        renderer,
        source_semantics,
    );
    const terminal_vt = terminalVtModule(
        b,
        target,
        optimize,
        renderer,
        source_semantics,
        vt,
    );
    module.addImport("adapter", adapter);
    module.addImport("terminal", terminal_vt);
    test_module.addImport("adapter", adapter);
    test_module.addImport("terminal", terminal_vt);

    const direct_tests = b.addTest(.{
        .name = "howl-render-direct",
        .root_module = test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    check.dependOn(&direct_tests.step);
    test_step.dependOn(&b.addRunArtifact(direct_tests).step);

    b.default_step = check;
}

fn rendererModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    limits: *std.Build.Module,
    source: *std.Build.Module,
    text: *std.Build.Module,
) *std.Build.Module {
    const renderer = b.createModule(.{
        .root_source_file = b.path("src/renderer.zig"),
        .target = target,
        .optimize = optimize,
    });
    renderer.addImport("limits", limits);
    renderer.addImport("source", source);
    renderer.addImport("howl_text", text);
    return renderer;
}

fn adapterModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    renderer: *std.Build.Module,
    source: *std.Build.Module,
) *std.Build.Module {
    const adapter = b.createModule(.{
        .root_source_file = b.path("src/adapter.zig"),
        .target = target,
        .optimize = optimize,
    });
    adapter.addImport("renderer", renderer);
    adapter.addImport("source", source);
    return adapter;
}

fn terminalVtModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    renderer: *std.Build.Module,
    source: *std.Build.Module,
    vt: *std.Build.Module,
) *std.Build.Module {
    const terminal = b.createModule(.{
        .root_source_file = b.path("src/terminal_vt.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal.addImport("renderer", renderer);
    terminal.addImport("source", source);
    terminal.addImport("howl_vt", vt);
    return terminal;
}
