const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const native_enabled = b.option(
        bool,
        "native_text",
        "Expose terminal presentation backed by howl-text",
    ) orelse true;
    const bundled_text = b.option(
        bool,
        "bundled_text",
        "Build howl-text with its pinned target FreeType/HarfBuzz sources",
    ) orelse false;
    if (bundled_text and !native_enabled)
        @panic("bundled_text requires native_text");

    const root_source = if (native_enabled)
        b.path("src/root_native.zig")
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

    const presentation = b.createModule(.{
        .root_source_file = b.path("src/presentation.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("presentation", presentation);
    test_module.addImport("presentation", presentation);

    var client: ?*std.Build.Module = null;
    var text: ?*std.Build.Module = null;
    var text_test_fonts: ?*std.Build.Module = null;
    if (native_enabled) {
        const client_dependency = b.dependency("howl_client", .{
            .target = target,
            .optimize = optimize,
        });
        client = client_dependency.module("howl_client");

        const text_dependency = b.dependency("howl_text", .{
            .target = target,
            .optimize = optimize,
            .bundled = bundled_text,
        });
        text = text_dependency.module("howl_text");
        text_test_fonts = text_dependency.module("howl_text_test_fonts");

        module.addImport("howl_text", text.?);
        test_module.addImport("howl_text", text.?);

        module.addImport("terminal", terminalNativeModule(
            b,
            target,
            optimize,
            client.?,
            text.?,
        ));
        test_module.addImport("terminal", terminalNativeModule(
            b,
            target,
            optimize,
            client.?,
            text.?,
        ));
    }

    const selected = b.addOptions();
    selected.addOption(bool, "native_text", native_enabled);
    const capability_tests = b.createModule(.{
        .root_source_file = b.path("src/capability_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    capability_tests.addImport("howl_render", test_module);
    capability_tests.addImport("selected_capabilities", selected.createModule());
    if (client) |value| capability_tests.addImport("howl_client", value);
    if (text) |value| capability_tests.addImport("howl_text", value);
    if (text_test_fonts) |fonts| capability_tests.addImport("test_fonts", fonts);

    const tests = b.addTest(.{
        .name = "howl-render-capabilities",
        .root_module = capability_tests,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile selected drawing and terminal-presentation proofs");
    check.dependOn(&tests.step);

    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    const test_step = b.step("test", "Run selected drawing and terminal-presentation proofs");
    test_step.dependOn(&run_tests.step);

    if (native_enabled) {
        const terminal_test_module = b.createModule(.{
            .root_source_file = b.path("src/terminal_test.zig"),
            .target = target,
            .optimize = optimize,
        });
        terminal_test_module.addImport("howl_render", test_module);
        terminal_test_module.addImport("howl_client", client.?);
        terminal_test_module.addImport("howl_text", text.?);
        terminal_test_module.addImport("test_fonts", text_test_fonts.?);
        const terminal_tests = b.addTest(.{
            .name = "howl-render-terminal-residency",
            .root_module = terminal_test_module,
            .filters = &.{"terminal Canvas owns final atlas residency and recovers after backend loss"},
            .use_llvm = false,
            .use_lld = false,
        });
        check.dependOn(&terminal_tests.step);
        const run_terminal_tests = b.addRunArtifact(terminal_tests);
        run_terminal_tests.addPassthruArgs();
        test_step.dependOn(&run_terminal_tests.step);
    }

    b.default_step = check;
}

fn terminalNativeModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, client: *std.Build.Module, text: *std.Build.Module) *std.Build.Module {
    const terminal = b.createModule(.{
        .root_source_file = b.path("src/terminal.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal.addImport("howl_client", client);
    terminal.addImport("howl_text", text);
    return terminal;
}
