const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const headers = b.addWriteFiles();
    const header = headers.add("howl-pty.h",
        \\#include <pty.h>
        \\
    );
    const translate = b.addTranslateC(.{
        .root_source_file = header,
        .target = target,
        .optimize = optimize,
    });
    translate.defineCMacro("_FORTIFY_SOURCE", "0");
    const c = translate.createModule();
    const module = b.addModule("howl_pty", .{
        .root_source_file = b.path("src/howl_pty.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addImport("pty_c", c);
    const tests = b.addTest(.{
        .name = "howl-pty",
        .root_module = module,
        .use_llvm = false,
        .use_lld = false,
    });
    const check = b.step("check", "Compile the Linux PTY owner and lifecycle proofs");
    check.dependOn(&tests.step);
    const run_tests = b.addRunArtifact(tests);
    run_tests.addPassthruArgs();
    b.step("test", "Run the Linux PTY lifecycle proofs").dependOn(&run_tests.step);
    b.default_step = check;
}
