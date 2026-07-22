const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("howl_text", .{
        .root_source_file = b.path("src/howl_text.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.linkSystemLibrary("freetype", .{});
    module.linkSystemLibrary("harfbuzz", .{});

    const fonts = b.addOptions();
    fonts.addOption([]const u8, "primary_font", b.pathFromRoot("testdata/primary.ttf"));
    fonts.addOption([]const u8, "symbol_font", b.pathFromRoot("testdata/symbols.ttf"));
    fonts.addOption([]const u8, "mono_font", b.pathFromRoot("testdata/mono.bdf"));
    const test_fonts = fonts.createModule();
    module.addImport("test_fonts", test_fonts);
    const tests_module = b.createModule(.{
        .root_source_file = b.path("src/test.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    tests_module.addImport("howl_text", module);
    tests_module.addImport("test_fonts", test_fonts);
    const tests = b.addTest(.{ .name = "howl-text", .root_module = tests_module, .filters = b.args orelse &.{} });
    tests.use_llvm = true;
    const check = b.step("check", "Compile the text module and owned font proofs");
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    if (b.args != null) run_tests.has_side_effects = true;
    b.step("test", "Run the owned text and font proofs").dependOn(&run_tests.step);
    b.default_step = check;
}
