const std = @import("std");
const vt_build = @import("howl_vt");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const static_gui = b.option(bool, "static-gui", "Build pinned SDL3/SDL3_ttf and FreeType/HarfBuzz statically (native Linux)") orelse false;
    const bundled_sdl = if (static_gui) b.dependency("sdl3", .{}) else null;
    const bundled_ttf = if (static_gui) b.dependency("sdl3_ttf", .{}) else null;
    const headers = b.addWriteFiles();
    const header = headers.add("desktop.h",
        \\#include <SDL3/SDL.h>
        \\#include <SDL3_ttf/SDL_ttf.h>
        \\#include <fontconfig/fontconfig.h>
        \\#include <sys/eventfd.h>
        \\#include <poll.h>
        \\#include <unistd.h>
        \\#include <errno.h>
        \\#include <fnmatch.h>
    );
    const translation = b.addTranslateC(.{ .root_source_file = header, .target = target, .optimize = optimize });
    // Keep the C API and linked archive at the same pinned SDL revisions.
    if (bundled_sdl) |sdl| translation.addIncludePath(sdl.path("include"));
    if (bundled_ttf) |ttf| translation.addIncludePath(ttf.path("include"));
    const pty = b.dependency("howl_pty", .{ .target = target, .optimize = optimize });
    const vt = b.dependency("howl_vt", .{ .target = target, .optimize = optimize });
    const text = b.dependency("howl_text", .{ .target = target, .optimize = optimize, .bundled = static_gui });
    const direct_output = vt_build.addOutputModules(b, vt.path("."), target, optimize, vt.module("howl_vt"), text.module("howl_text"), vt.module("howl_vt_output_commands"), vt.module("howl_vt_output_limits"));
    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    root.addImport("desktop", translation.createModule());
    root.addImport("howl_pty", pty.module("howl_pty"));
    root.addImport("howl_vt", vt.module("howl_vt"));
    root.addImport("howl_text", text.module("howl_text"));
    root.addImport("howl_vt_output", direct_output.owner);
    root.addImport("output_state", direct_output.owner.import_table.get("output_state").?);
    root.addImport("howl_vt_output_commands", vt.module("howl_vt_output_commands"));
    root.addImport("howl_vt_output_limits", vt.module("howl_vt_output_limits"));
    root.addImport("test_fonts", text.module("howl_text_test_fonts"));
    if (static_gui) {
        if (target.result.os.tag != .linux or target.result.cpu.arch != b.graph.host.result.cpu.arch or target.result.abi != b.graph.host.result.abi)
            // zig-audit: acknowledge panic
            // reason: Reject unsupported targets before linking host-native SDL objects against an incompatible architecture or ABI.
            @panic("static-gui currently supports native-architecture and ABI Linux only");
        const sdl = bundled_sdl.?;
        const ttf = bundled_ttf.?;
        const build_sdl = b.addSystemCommand(&.{"bash"});
        build_sdl.addFileArg(b.path("build-support/static-sdl.sh"));
        build_sdl.addDirectoryArg(sdl.path("."));
        build_sdl.addDirectoryArg(ttf.path("."));
        const output = build_sdl.addOutputDirectoryArg("sdl-static");
        root.addObjectFile(output.path(b, "ttf/libSDL3_ttf.a"));
        root.addObjectFile(output.path(b, "sdl/libSDL3.a"));
    } else {
        root.linkSystemLibrary("SDL3", .{});
        root.linkSystemLibrary("SDL3_ttf", .{});
    }
    root.linkSystemLibrary("fontconfig", .{});
    // Zig 0.17.0-dev.1980+e78ea8f2c: selfhost codegen inflated publication CPU.
    // Use LLVM for this desktop artifact and its proofs; keep the selfhost linker.
    const app = b.addExecutable(.{ .name = "howl-app", .root_module = root, .use_llvm = true, .use_lld = false });
    b.installArtifact(app);
    const tests = b.addTest(.{ .name = "howl-app", .root_module = root, .use_llvm = true, .use_lld = false });
    // Independent direct-composition proof uses the same VT/Text output identity
    // as the integrated app worker's Core and Projection.
    const direct_proof = b.createModule(.{ .root_source_file = b.path("src/direct_output_proof.zig"), .target = target, .optimize = optimize, .link_libc = true });
    direct_proof.addImport("howl_vt", vt.module("howl_vt"));
    direct_proof.addImport("howl_pty", pty.module("howl_pty"));
    direct_proof.addImport("howl_vt_output", direct_output.owner);
    direct_proof.addImport("output_state", direct_output.owner.import_table.get("output_state").?);
    direct_proof.addImport("test_fonts", text.module("howl_text_test_fonts"));
    const direct_tests = b.addTest(.{ .name = "howl-app-direct-output-ownership", .root_module = direct_proof, .use_llvm = true, .use_lld = false });
    const check = b.step("check", "Compile the direct Zig SDL app and its proofs");
    check.dependOn(&app.step);
    check.dependOn(&tests.step);
    check.dependOn(&direct_tests.step);
    const audit = b.step("audit", "Audit every owned Zig source file");
    const zig_audit = b.addSystemCommand(&.{ "zig-audit", "check" });
    zig_audit.setCwd(b.path("."));
    audit.dependOn(&zig_audit.step);
    check.dependOn(audit);
    const test_step = b.step("test", "Run application ownership and behavior proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    const direct_run = b.addRunArtifact(direct_tests);
    test_step.dependOn(&direct_run.step);
    b.step("test:direct-owner", "Prove independent VT/Text borrowed output without Render or Instance").dependOn(&direct_run.step);
    const run = b.addRunArtifact(app);
    run.addPassthruArgs();
    b.step("run", "Run howl-app").dependOn(&run.step);
    b.default_step = check;
}
