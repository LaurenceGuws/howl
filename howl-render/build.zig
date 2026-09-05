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
    const bundled_text = b.option(
        bool,
        "bundled_text",
        "Build howl-text with its pinned target FreeType/HarfBuzz sources",
    ) orelse false;
    if (bundled_text and !native_enabled)
        @panic("bundled_text requires native_text");
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

    var client: ?*std.Build.Module = null;
    var text: ?*std.Build.Module = null;
    var text_test_fonts: ?*std.Build.Module = null;
    if (native_enabled) {
        const client_dependency = b.dependency("howl_client", .{
            .target = target,
            .optimize = optimize,
        });
        client = client_dependency.module("howl_client");
        module.addImport("howl_client", client.?);
        test_module.addImport("howl_client", client.?);
        const dependency = b.dependency("howl_text", .{
            .target = target,
            .optimize = optimize,
            .bundled = bundled_text,
        });
        text = dependency.module("howl_text");
        text_test_fonts = dependency.module("howl_text_test_fonts");
        module.addImport("howl_text", text.?);
        test_module.addImport("howl_text", text.?);
    }
    if (native_enabled) {
        const production_chrome = chromeNativeModule(
            b,
            target,
            optimize,
            chrome,
            canvas,
            text.?,
        );
        module.addImport("chrome", production_chrome);
        module.addImport("terminal", terminalNativeModule(
            b,
            target,
            optimize,
            client.?,
            text.?,
            canvas,
        ));
        const tested_chrome = chromeNativeModule(
            b,
            target,
            optimize,
            chrome,
            canvas,
            text.?,
        );
        test_module.addImport("chrome", tested_chrome);
        test_module.addImport("terminal", terminalNativeModule(
            b,
            target,
            optimize,
            client.?,
            text.?,
            canvas,
        ));
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
    if (client) |value| capability_tests.addImport("howl_client", value);
    capability_tests.addImport("selected_capabilities", selected.createModule());
    if (text_test_fonts) |fonts| capability_tests.addImport("test_fonts", fonts);

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
    b.default_step = check;
}

fn chromeNativeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    chrome: *std.Build.Module,
    canvas: *std.Build.Module,
    text: *std.Build.Module,
) *std.Build.Module {
    const wrapper = b.createModule(.{
        .root_source_file = b.path("src/chrome_native.zig"),
        .target = target,
        .optimize = optimize,
    });
    wrapper.addImport("chrome_impl", chrome);
    wrapper.addImport("canvas", canvas);
    wrapper.addImport("howl_text", text);
    return wrapper;
}

fn terminalNativeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    client: *std.Build.Module,
    text: *std.Build.Module,
    canvas: *std.Build.Module,
) *std.Build.Module {
    const terminal = b.createModule(.{
        .root_source_file = b.path("src/terminal_native.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal.addImport("howl_client", client);
    terminal.addImport("howl_text", text);
    terminal.addImport("canvas", canvas);
    return terminal;
}
