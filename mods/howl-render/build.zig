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
    const audit = b.step("audit", "Audit every owned Zig source file");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    check.dependOn(audit);

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

    const vt_dependency = b.dependency("howl_vt", .{ .target = target, .optimize = optimize });
    const vt = vt_dependency.module("howl_vt");
    const text_dependency = b.dependency("howl_text", .{
        .target = target,
        .optimize = optimize,
        .bundled = bundled_text,
    });
    const text = text_dependency.module("howl_text");
    const cache_module = b.createModule(.{ .root_source_file = b.path("src/glyph_cache.zig"), .target = target, .optimize = optimize });
    cache_module.addImport("howl_text", text);
    cache_module.addImport("limits", limits);
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

    const background_root = b.createModule(.{ .root_source_file = b.path("test/background.zig"), .target = target, .optimize = optimize, .link_libc = true });
    background_root.addImport("howl_render", module);
    background_root.addImport("howl_vt", vt);
    background_root.addImport("test_fonts", text_dependency.module("howl_text_test_fonts"));
    const background_tests = b.addTest(.{ .name = "howl-render-background", .root_module = background_root, .use_llvm = false, .use_lld = false });
    check.dependOn(&background_tests.step);
    test_step.dependOn(&b.addRunArtifact(background_tests).step);

    const native_types = b.addTranslateC(.{ .root_source_file = b.path("include/howl_render_native.h"), .target = target, .optimize = optimize });
    const native = b.addModule("howl_render_native", .{ .root_source_file = b.path("src/native.zig"), .target = target, .optimize = optimize });
    native.addImport("renderer", renderer);
    native.addImport("render_native_types", native_types.createModule());
    b.addNamedLazyPath("howl_render_native_header", b.path("include/howl_render_native.h"));
    // Existing native remains the schema/projection leaf. Standalone ownership
    // is separately selectable and never imported merely for those records.
    const owner_native = b.addModule("howl_render_owner_native", .{ .root_source_file = b.path("src/native_owner.zig"), .target = target, .optimize = optimize });
    owner_native.addImport("howl_render", module);
    owner_native.addImport("howl_render_native", native);
    owner_native.addImport("howl_vt_native", vt_dependency.module("howl_vt_native"));
    const abi_root = b.createModule(.{ .root_source_file = b.path("src/abi.zig"), .target = target, .optimize = optimize, .link_libc = true });
    abi_root.addImport("howl_render_owner_native", owner_native);
    const abi = b.addLibrary(.{ .name = "howl_render_native", .linkage = .static, .root_module = abi_root, .use_llvm = false, .use_lld = false });
    abi.installHeader(b.path("include/howl_render_native.h"), "howl_render_native.h");
    b.installArtifact(abi);
    b.installArtifact(vt_dependency.artifact("howl_vt_native"));
    check.dependOn(&abi.step);

    const native_tests = b.addTest(.{ .name = "howl-render-native", .root_module = native, .use_llvm = false, .use_lld = false });
    check.dependOn(&native_tests.step);
    const native_run = b.addRunArtifact(native_tests);
    test_step.dependOn(&native_run.step);
    b.step("test:native", "Run the Render-owned native payload proofs").dependOn(&native_run.step);

    const owner_root = b.createModule(.{ .root_source_file = b.path("test/native_owner.zig"), .target = target, .optimize = optimize, .link_libc = true });
    owner_root.addImport("howl_render_owner_native", owner_native);
    owner_root.addImport("howl_render_native", native);
    owner_root.addImport("howl_render", module);
    owner_root.addImport("howl_vt_native", vt_dependency.module("howl_vt_native"));
    owner_root.addImport("test_fonts", text_dependency.module("howl_text_test_fonts"));
    owner_root.addAnonymousImport("font_data", .{ .root_source_file = text_dependency.namedLazyPath("howl_text_test_font") });
    const owner_tests = b.addTest(.{ .name = "howl-render-owner", .root_module = owner_root, .use_llvm = false, .use_lld = false });
    check.dependOn(&owner_tests.step);
    const owner_run = b.addRunArtifact(owner_tests);
    test_step.dependOn(&owner_run.step);
    b.step("test:owner", "Run standalone Render lifetime/frame/allocation proofs").dependOn(&owner_run.step);

    const foreign_root = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    foreign_root.linkLibrary(abi);
    foreign_root.linkLibrary(vt_dependency.artifact("howl_vt_native"));
    foreign_root.addCSourceFile(.{ .file = b.path("test/native_client.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
    foreign_root.addCSourceFile(.{ .file = b.path("test/header.cpp"), .flags = &.{ "-std=c++17", "-Wall", "-Wextra", "-Werror" } });
    const foreign = b.addExecutable(.{ .name = "howl-render-foreign", .root_module = foreign_root, .use_llvm = false, .use_lld = false });
    check.dependOn(&foreign.step);
    const foreign_run = b.addRunArtifact(foreign);
    foreign_run.addFileArg(text_dependency.namedLazyPath("howl_text_test_font"));
    test_step.dependOn(&foreign_run.step);
    b.step("test:foreign", "Run C/C++ against exact Render/VT artifacts and installed headers").dependOn(&foreign_run.step);
    // The embedder may place these archives in its own language/runtime shim.
    const shared_root = b.createModule(.{ .root_source_file = b.path("test/static_embedding.zig"), .target = target, .optimize = optimize, .link_libc = true });
    shared_root.linkLibrary(abi);
    shared_root.linkLibrary(vt_dependency.artifact("howl_vt_native"));
    shared_root.addCSourceFile(.{ .file = b.path("test/native_client.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror", "-Dmain=howl_render_static_c" } });
    shared_root.addCSourceFile(.{ .file = b.path("test/header.cpp"), .flags = &.{ "-std=c++17", "-Wall", "-Wextra", "-Werror" } });
    const shared = b.addLibrary(.{ .name = "howl_render_static_embedding", .linkage = .dynamic, .root_module = shared_root, .use_llvm = false, .use_lld = false });
    const shared_driver_root = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    shared_driver_root.linkLibrary(shared);
    shared_driver_root.addCSourceFile(.{ .file = b.path("test/static_embedding.c"), .flags = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" } });
    const shared_driver = b.addExecutable(.{ .name = "howl-render-static-embedding", .root_module = shared_driver_root, .use_llvm = false, .use_lld = false });
    check.dependOn(&shared_driver.step);
    const shared_run = b.addRunArtifact(shared_driver);
    shared_run.addFileArg(text_dependency.namedLazyPath("howl_text_test_font"));
    test_step.dependOn(&shared_run.step);
    b.step("test:static-embedding", "Qualify static Render ABI inside a foreign shared library").dependOn(&shared_run.step);

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
