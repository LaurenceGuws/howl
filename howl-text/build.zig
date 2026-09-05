const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const native_c = nativeCModule(b, target, optimize);

    const module = b.addModule("howl_text", .{
        .root_source_file = b.path("src/text.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addImport("native_c", native_c);
    module.linkSystemLibrary("freetype", .{});
    module.linkSystemLibrary("harfbuzz", .{});

    const fonts = b.addOptions();
    fonts.addOption([]const u8, "primary_font", b.root.joinString(b.allocator, "testdata/primary.ttf") catch @panic("OOM"));
    fonts.addOption([]const u8, "symbol_font", b.root.joinString(b.allocator, "testdata/symbols.ttf") catch @panic("OOM"));
    fonts.addOption([]const u8, "normal_ligature_font", b.root.joinString(b.allocator, "testdata/fira-code-medium.otf") catch @panic("OOM"));
    fonts.addOption([]const u8, "mono_font", b.root.joinString(b.allocator, "testdata/mono.bdf") catch @panic("OOM"));
    const test_fonts = b.addModule("howl_text_test_fonts", .{
        .root_source_file = fonts.getOutput(),
    });

    const tested = b.createModule(.{
        .root_source_file = b.path("src/text.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tested.addImport("native_c", native_c);
    tested.addImport("test_fonts", test_fonts);
    tested.linkSystemLibrary("freetype", .{});
    tested.linkSystemLibrary("harfbuzz", .{});

    const tests = b.addTest(.{
        .name = "howl-text",
        .root_module = tested,
        .use_llvm = false,
        .use_lld = false,
    });

    const contract = b.createModule(.{
        .root_source_file = b.path("src/native_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    contract.addImport("howl_text", tested);
    contract.addImport("test_fonts", test_fonts);
    const contract_tests = b.addTest(.{
        .name = "howl-text-contract",
        .root_module = contract,
        .use_llvm = false,
        .use_lld = false,
    });

    const check = b.step("check", "Compile native text shaping and rasterization proofs");
    check.dependOn(&tests.step);
    check.dependOn(&contract_tests.step);

    const test_step = b.step("test", "Run native text shaping and rasterization proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(contract_tests).step);
    b.default_step = check;
}

fn nativeCModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Module {
    const headers = b.addWriteFiles();
    const header = headers.add("howl-text-native.h",
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
