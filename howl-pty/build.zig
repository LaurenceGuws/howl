const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const windows = target.result.os.tag == .windows;
    const module = b.addModule("howl_pty", .{
        .root_source_file = b.path(if (windows) "src/howl_pty_windows.zig" else "src/howl_pty.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (windows) module.linkSystemLibrary("kernel32", .{});
    const tests = b.addTest(.{
        .name = "howl-pty",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the platform PTY owner and lifecycle proofs");
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    b.step("test", "Run the platform PTY lifecycle proofs").dependOn(&run_tests.step);
    b.default_step = check;
}
