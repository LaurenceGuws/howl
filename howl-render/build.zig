const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const native_enabled = b.option(
        bool,
        "native_text",
        "Expose native FreeType/HarfBuzz text shaping and rasterization",
    ) orelse true;
    const generated_api_enabled = b.option(
        bool,
        "generated_glyphs",
        "Expose the standalone generated terminal-glyph API",
    ) orelse true;
    const vt_dependency = b.dependency("howl_vt", .{
        .target = target,
        .optimize = optimize,
    });
    const vt_module = vt_dependency.module("howl_vt");
    const root_source = if (native_enabled and generated_api_enabled)
        b.path("src/root_native_generated.zig")
    else if (native_enabled)
        b.path("src/root_native.zig")
    else if (generated_api_enabled)
        b.path("src/root_generated.zig")
    else
        b.path("src/root.zig");
    const module = b.addModule("howl_render", .{
        .root_source_file = root_source,
        .target = target,
        .optimize = optimize,
    });
    module.addImport("howl_vt", vt_module);
    const test_module = b.createModule(.{
        .root_source_file = root_source,
        .target = target,
        .optimize = optimize,
    });
    test_module.addImport("howl_vt", vt_module);
    const canvas_validation = b.createModule(.{
        .root_source_file = b.path("src/canvas_validation.zig"),
        .target = target,
        .optimize = optimize,
    });
    const canvas = b.createModule(.{
        .root_source_file = b.path("src/canvas.zig"),
        .target = target,
        .optimize = optimize,
    });
    canvas.addImport("canvas_validation", canvas_validation);
    module.addImport("canvas", canvas);
    test_module.addImport("canvas", canvas);
    const chrome = b.createModule(.{
        .root_source_file = b.path("src/chrome.zig"),
        .target = target,
        .optimize = optimize,
    });
    chrome.addImport("canvas", canvas);

    var test_fonts: ?*std.Build.Module = null;
    var production_native: ?*std.Build.Module = null;
    var tested_native: ?*std.Build.Module = null;
    if (native_enabled) {
        const native_c = nativeCModule(b, target, optimize);
        const fonts = b.addOptions();
        fonts.addOption(
            []const u8,
            "primary_font",
            b.root.joinString(b.allocator, "testdata/primary.ttf") catch @panic("OOM"),
        );
        fonts.addOption(
            []const u8,
            "symbol_font",
            b.root.joinString(b.allocator, "testdata/symbols.ttf") catch @panic("OOM"),
        );
        fonts.addOption(
            []const u8,
            "normal_ligature_font",
            b.root.joinString(
                b.allocator,
                "testdata/fira-code-medium.otf",
            ) catch @panic("OOM"),
        );
        fonts.addOption(
            []const u8,
            "mono_font",
            b.root.joinString(b.allocator, "testdata/mono.bdf") catch @panic("OOM"),
        );
        test_fonts = fonts.createModule();
        const native = nativeModule(b, target, optimize, native_c);
        production_native = native;
        module.addImport("native_text", native);
        const tested = nativeModule(b, target, optimize, native_c);
        tested.addImport("test_fonts", test_fonts.?);
        tested_native = tested;
        test_module.addImport("native_text", tested);
    }
    if (native_enabled) {
        const production_chrome = chromeNativeModule(
            b,
            target,
            optimize,
            chrome,
            canvas,
            production_native.?,
        );
        module.addImport("chrome", production_chrome);
        const tested_chrome = chromeNativeModule(
            b,
            target,
            optimize,
            chrome,
            canvas,
            tested_native.?,
        );
        test_module.addImport("chrome", tested_chrome);
    } else {
        module.addImport("chrome", chrome);
        test_module.addImport("chrome", chrome);
    }
    if (generated_api_enabled) {
        const generated = b.createModule(.{
            .root_source_file = b.path("src/generated.zig"),
            .target = target,
            .optimize = optimize,
        });
        module.addImport("generated_glyphs", generated);
        test_module.addImport("generated_glyphs", generated);
    }
    const selected = b.addOptions();
    selected.addOption(bool, "native_text", native_enabled);
    selected.addOption(bool, "generated_glyphs", generated_api_enabled);
    const capability_tests = b.createModule(.{
        .root_source_file = b.path("src/capability_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    capability_tests.addImport("howl_render", test_module);
    capability_tests.addImport("canvas", canvas);
    capability_tests.addImport("selected_capabilities", selected.createModule());
    if (test_fonts) |fonts| capability_tests.addImport("test_fonts", fonts);

    const tests = b.addTest(.{
        .name = "howl-render-capabilities",
        .root_module = capability_tests,
        .use_llvm = false,
        .use_lld = false,
    });
    const terminal_test_module = b.createModule(.{
        .root_source_file = b.path("src/terminal_cells.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal_test_module.addImport("howl_vt", vt_module);
    const terminal_tests = b.addTest(.{
        .name = "howl-render-terminal-cells",
        .root_module = terminal_test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the selected rendering capability and proofs");
    check.dependOn(&tests.step);
    check.dependOn(&terminal_tests.step);
    const run_tests = b.addRunArtifact(tests);
    const run_terminal_tests = b.addRunArtifact(terminal_tests);
    run_tests.addPassthruArgs();
    run_terminal_tests.addPassthruArgs();
    const test_step = b.step("test", "Run the selected rendering capability proofs");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_terminal_tests.step);
    b.default_step = check;
}

fn chromeNativeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    chrome: *std.Build.Module,
    canvas: *std.Build.Module,
    native: *std.Build.Module,
) *std.Build.Module {
    const wrapper = b.createModule(.{
        .root_source_file = b.path("src/chrome_native.zig"),
        .target = target,
        .optimize = optimize,
    });
    wrapper.addImport("chrome_impl", chrome);
    wrapper.addImport("canvas", canvas);
    wrapper.addImport("native_text", native);
    return wrapper;
}

fn nativeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    native_c: *std.Build.Module,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("src/native_text.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addImport("native_c", native_c);
    module.linkSystemLibrary("freetype", .{});
    module.linkSystemLibrary("harfbuzz", .{});
    return module;
}

fn nativeCModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const headers = b.addWriteFiles();
    const header = headers.add("howl-render-native.h",
        \\#include <ft2build.h>
        \\#include <freetype/freetype.h>
        \\#include <freetype/tttables.h>
        \\#include <harfbuzz/hb.h>
        \\#include <harfbuzz/hb-ft.h>
        \\
    );
    const translate = b.addTranslateC(.{
        .root_source_file = header,
        .target = target,
        .optimize = optimize,
    });
    translate.linkSystemLibrary("freetype", .{});
    translate.linkSystemLibrary("harfbuzz", .{});
    return translate.createModule();
}
