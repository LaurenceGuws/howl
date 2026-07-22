const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("howl_pty", .{
        .root_source_file = b.path("src/howl_pty.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addCMacro("_FORTIFY_SOURCE", "0");
    const tests = b.addTest(.{ .name = "howl-pty", .root_module = module, .filters = b.args orelse &.{} });
    tests.use_llvm = true;
    const check = b.step("check", "Compile the Linux PTY owner and lifecycle proofs");
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    if (b.args != null) run_tests.has_side_effects = true;
    b.step("test", "Run the Linux PTY lifecycle proofs").dependOn(&run_tests.step);
    b.default_step = check;
}
