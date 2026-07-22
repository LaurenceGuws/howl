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

    var test_fonts: ?*std.Build.Module = null;
    var production_native: ?*std.Build.Module = null;
    var tested_native: ?*std.Build.Module = null;
    if (native_enabled) {
        const fonts = b.addOptions();
        fonts.addOption([]const u8, "primary_font", b.pathFromRoot("testdata/primary.ttf"));
        fonts.addOption([]const u8, "symbol_font", b.pathFromRoot("testdata/symbols.ttf"));
        fonts.addOption([]const u8, "mono_font", b.pathFromRoot("testdata/mono.bdf"));
        test_fonts = fonts.createModule();
        const native = nativeModule(b, target, optimize);
        production_native = native;
        module.addImport("native_text", native);
        const tested = nativeModule(b, target, optimize);
        tested.addImport("test_fonts", test_fonts.?);
        tested_native = tested;
        test_module.addImport("native_text", tested);
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
    if (terminal_enabled) {
        const vt = (b.lazyDependency("howl_vt", .{
            .target = target,
            .optimize = optimize,
        }) orelse return).module("howl_vt");
        const terminal = b.createModule(.{
            .root_source_file = b.path("src/terminal.zig"),
            .target = target,
            .optimize = optimize,
        });
        terminal.addImport("howl_vt", vt);
        terminal_module = terminal;
        module.addImport("terminal_projection", terminal);
        test_module.addImport("terminal_projection", terminal);
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
        const production_text = terminalTextModule(
            b,
            target,
            optimize,
            native_enabled,
            generated_enabled,
            terminal_module.?,
            production_native,
            generated_module,
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
        );
        test_module.addImport("terminal_text_capability", tested_text);
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
    capability_tests.addImport("selected_capabilities", selected.createModule());
    if (test_fonts) |fonts| capability_tests.addImport("test_fonts", fonts);

    const tests = b.addTest(.{
        .name = "howl-render-capabilities",
        .root_module = capability_tests,
        .filters = b.args orelse &.{},
    });
    tests.use_llvm = true;
    const check = b.step("check", "Compile the selected rendering capability and proofs");
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    if (b.args != null) run_tests.has_side_effects = true;
    const test_step = b.step("test", "Run the selected rendering capability proofs");
    test_step.dependOn(&run_tests.step);
    if (terminal_proofs) |proofs| {
        const proof_tests = b.addTest(.{
            .name = "howl-render-terminal-proofs",
            .root_module = proofs,
            .filters = b.args orelse &.{},
        });
        proof_tests.use_llvm = true;
        check.dependOn(&proof_tests.step);
        const run_proofs = b.addRunArtifact(proof_tests);
        if (b.args != null) run_proofs.has_side_effects = true;
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
    const options = b.addOptions();
    options.addOption(bool, "native_text", native_enabled);
    options.addOption(bool, "generated_glyphs", generated_enabled);
    const impl = b.createModule(.{
        .root_source_file = b.path("src/terminal_text.zig"),
        .target = target,
        .optimize = optimize,
    });
    impl.addImport("terminal_text_features", options.createModule());
    impl.addImport("terminal_projection", terminal);
    if (native) |selected| impl.addImport("native_text", selected);
    if (generated) |selected| impl.addImport("generated_glyphs", selected);
    capability.addImport("terminal_text_impl", impl);
    return capability;
}

fn nativeModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const module = b.createModule(.{
        .root_source_file = b.path("src/native_text.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.linkSystemLibrary("freetype", .{});
    module.linkSystemLibrary("harfbuzz", .{});
    return module;
}
