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

    const root_source = if (native_enabled and generated_enabled)
        b.path("src/root_all.zig")
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
    if (native_enabled) {
        const fonts = b.addOptions();
        fonts.addOption([]const u8, "primary_font", b.pathFromRoot("testdata/primary.ttf"));
        fonts.addOption([]const u8, "symbol_font", b.pathFromRoot("testdata/symbols.ttf"));
        fonts.addOption([]const u8, "mono_font", b.pathFromRoot("testdata/mono.bdf"));
        test_fonts = fonts.createModule();
        const native = nativeModule(b, target, optimize);
        module.addImport("native_text", native);
        const tested_native = nativeModule(b, target, optimize);
        tested_native.addImport("test_fonts", test_fonts.?);
        test_module.addImport("native_text", tested_native);
    }
    if (generated_enabled) {
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
    selected.addOption(bool, "generated_glyphs", generated_enabled);
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
    b.step("test", "Run the selected rendering capability proofs").dependOn(&run_tests.step);
    b.default_step = check;
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
