const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const native_enabled = b.option(
        bool,
        "native_text",
        "Expose native FreeType/HarfBuzz text shaping and rasterization",
    ) orelse true;
    const generated_enabled = b.option(
        bool,
        "generated_glyphs",
        "Expose generated terminal-glyph rasterization",
    ) orelse true;
    const terminal_enabled = b.option(
        bool,
        "terminal",
        "Expose VT semantic-to-visual terminal projection",
    ) orelse true;

    const root_source = if (terminal_enabled and native_enabled and generated_enabled)
        b.path("src/root_all.zig")
    else if (terminal_enabled and native_enabled)
        b.path("src/root_terminal_native.zig")
    else if (terminal_enabled and generated_enabled)
        b.path("src/root_terminal_generated.zig")
    else if (terminal_enabled)
        b.path("src/root_terminal.zig")
    else if (native_enabled and generated_enabled)
        b.path("src/root_native_generated.zig")
    else if (native_enabled)
        b.path("src/root_native.zig")
    else if (generated_enabled)
        b.path("src/root_generated.zig")
    else
        b.path("src/root.zig");
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
    var generated_module: ?*std.Build.Module = null;
    if (generated_enabled) {
        const generated = b.createModule(.{
            .root_source_file = b.path("src/generated.zig"),
            .target = target,
            .optimize = optimize,
        });
        generated_module = generated;
        module.addImport("generated_glyphs", generated);
        test_module.addImport("generated_glyphs", generated);
    }
    var terminal_proofs: ?*std.Build.Module = null;
    var terminal_module: ?*std.Build.Module = null;
    var image_module: ?*std.Build.Module = null;
    if (terminal_enabled) {
        const vt = (b.lazyDependency("howl_vt", .{
            .target = target,
            .optimize = optimize,
        }) orelse return).module("howl_vt");
        const terminal = b.createModule(.{
            .root_source_file = b.path("src/terminal_projection.zig"),
            .target = target,
            .optimize = optimize,
        });
        terminal.addImport("howl_vt", vt);
        terminal_module = terminal;
        const images = b.createModule(.{
            .root_source_file = b.path("src/image_projection.zig"),
            .target = target,
            .optimize = optimize,
        });
        images.addImport("howl_vt", vt);
        image_module = images;
        module.addImport("image_projection", images);
        test_module.addImport("image_projection", images);
        const proofs = b.createModule(.{
            .root_source_file = b.path("src/terminal_test.zig"),
            .target = target,
            .optimize = optimize,
        });
        proofs.addImport("howl_render", test_module);
        proofs.addImport("howl_vt", vt);
        terminal_proofs = proofs;
    }
    if (terminal_enabled and (native_enabled or generated_enabled)) {
        const terminal_features = b.addOptions();
        terminal_features.addOption(bool, "native_text", native_enabled);
        terminal_features.addOption(bool, "generated_glyphs", generated_enabled);
        const terminal_features_module = terminal_features.createModule();
        const production_text = terminalTextModule(
            b,
            target,
            optimize,
            native_enabled,
            generated_enabled,
            terminal_module.?,
            production_native,
            generated_module,
            terminal_features_module,
        );
        module.addImport("terminal_text_capability", production_text);
        const tested_text = terminalTextModule(
            b,
            target,
            optimize,
            native_enabled,
            generated_enabled,
            terminal_module.?,
            tested_native,
            generated_module,
            terminal_features_module,
        );
        test_module.addImport("terminal_text_capability", tested_text);

        const production_terminal = b.createModule(.{
            .root_source_file = b.path("src/terminal_canvas.zig"),
            .target = target,
            .optimize = optimize,
        });
        production_terminal.addImport("terminal_projection_impl", terminal_module.?);
        production_terminal.addImport("image_projection", image_module.?);
        production_terminal.addImport("terminal_text_capability", production_text);
        production_terminal.addImport("canvas", canvas);
        production_terminal.addImport("canvas_validation", canvas_validation);
        production_terminal.addImport("terminal_canvas_features", terminal_features_module);
        module.addImport("terminal_projection", production_terminal);

        const tested_terminal = b.createModule(.{
            .root_source_file = b.path("src/terminal_canvas.zig"),
            .target = target,
            .optimize = optimize,
        });
        tested_terminal.addImport("terminal_projection_impl", terminal_module.?);
        tested_terminal.addImport("image_projection", image_module.?);
        tested_terminal.addImport("terminal_text_capability", tested_text);
        tested_terminal.addImport("canvas", canvas);
        tested_terminal.addImport("canvas_validation", canvas_validation);
        tested_terminal.addImport("terminal_canvas_features", terminal_features_module);
        test_module.addImport("terminal_projection", tested_terminal);
    }
    if (terminal_enabled and !(native_enabled or generated_enabled)) {
        module.addImport("terminal_projection", terminal_module.?);
        test_module.addImport("terminal_projection", terminal_module.?);
    }

    const selected = b.addOptions();
    selected.addOption(bool, "native_text", native_enabled);
    selected.addOption(bool, "generated_glyphs", generated_enabled);
    selected.addOption(bool, "terminal", terminal_enabled);
    selected.addOption(bool, "terminal_text", terminal_enabled and (native_enabled or generated_enabled));
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
    const check = b.step("check", "Compile the selected rendering capability and proofs");
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    const test_step = b.step("test", "Run the selected rendering capability proofs");
    test_step.dependOn(&run_tests.step);
    if (terminal_proofs) |proofs| {
        const proof_tests = b.addTest(.{
            .name = "howl-render-terminal-proofs",
            .root_module = proofs,
            .use_llvm = false,
            .use_lld = false,
        });
        check.dependOn(&proof_tests.step);
        const run_proofs = b.addRunArtifact(proof_tests);
        run_proofs.addPassthruArgs();
        test_step.dependOn(&run_proofs.step);
    }
    b.default_step = check;
}

fn terminalTextModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    native_enabled: bool,
    generated_enabled: bool,
    terminal: *std.Build.Module,
    native: ?*std.Build.Module,
    generated: ?*std.Build.Module,
    features: *std.Build.Module,
) *std.Build.Module {
    const root = if (native_enabled and generated_enabled)
        b.path("src/terminal_text_all.zig")
    else if (native_enabled)
        b.path("src/terminal_text_native.zig")
    else
        b.path("src/terminal_text_generated.zig");
    const capability = b.createModule(.{
        .root_source_file = root,
        .target = target,
        .optimize = optimize,
    });
    const impl = b.createModule(.{
        .root_source_file = b.path("src/terminal_text.zig"),
        .target = target,
        .optimize = optimize,
    });
    impl.addImport("terminal_text_features", features);
    impl.addImport("terminal_projection", terminal);
    if (native) |selected| impl.addImport("native_text", selected);
    if (generated) |selected| impl.addImport("generated_glyphs", selected);
    capability.addImport("terminal_text_impl", impl);
    return capability;
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
