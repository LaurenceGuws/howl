const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("howl_vk", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const proof_module = b.createModule(.{
        .root_source_file = b.path("src/proofs.zig"),
        .target = target,
        .optimize = optimize,
    });
    proof_module.addImport("howl_vk", module);
    const tests = b.addTest(.{ .root_module = proof_module, .use_llvm = false, .use_lld = false });
    tests.root_module.linkSystemLibrary("vulkan", .{});
    const terminal_test_module = b.createModule(.{
        .root_source_file = b.path("src/terminal_cells.zig"),
        .target = target,
        .optimize = optimize,
    });
    const terminal_tests = b.addTest(.{
        .name = "howl-vk-terminal-cells",
        .root_module = terminal_test_module,
        .use_llvm = false,
        .use_lld = false,
    });
    terminal_tests.root_module.linkSystemLibrary("vulkan", .{});
    const check = b.step("check", "Compile the curated Vulkan module");
    check.dependOn(&tests.step);
    check.dependOn(&terminal_tests.step);
    const run_tests = b.addRunArtifact(tests);
    const run_terminal_tests = b.addRunArtifact(terminal_tests);
    const test_step = b.step("test", "Run Vulkan ABI and dispatch proofs");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_terminal_tests.step);
    b.default_step = check;
}
