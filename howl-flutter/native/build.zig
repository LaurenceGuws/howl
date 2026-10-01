const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const repo = b.option([]const u8, "repo", "Howl repository root") orelse
        @panic("native host requires -Drepo=/path/to/howl");
    const ndk = b.option([]const u8, "ndk", "Android NDK root");
    const deps = b.option([]const u8, "deps", "private FreeType/HarfBuzz prefix");
    const freetype_include = b.option([]const u8, "freetype-include", "FreeType include directory");
    const harfbuzz_include = b.option([]const u8, "harfbuzz-include", "HarfBuzz include root");
    const apple_sdk = b.option([]const u8, "apple-sdk", "Apple SDK root for Darwin translate-c");

    const translate = b.addTranslateC(.{
        .root_source_file = b.path("native.h"),
        .target = target,
        .optimize = optimize,
    });
    if (ndk) |ndk_root| {
        const prefix = deps orelse @panic("Android native host requires -Ddeps=/path/to/prefix");
        const include = b.pathJoin(&.{ ndk_root, "toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include" });
        translate.addSystemIncludePath(b.path("ndk-overlay"));
        translate.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ prefix, "include/freetype2" }) });
        translate.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ prefix, "include" }) });
        translate.addSystemIncludePath(.{ .cwd_relative = include });
        translate.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ include, "aarch64-linux-android" }) });
    } else {
        if (freetype_include) |path| translate.addIncludePath(.{ .cwd_relative = path });
        if (harfbuzz_include) |path| translate.addIncludePath(.{ .cwd_relative = path });
        if (apple_sdk) |sdk| {
            translate.addSystemIncludePath(.{ .cwd_relative = b.pathJoin(&.{ sdk, "usr/include" }) });
        }
    }
    const native_c = translate.createModule();

    // Reuse package-owned client/Local/Server/VT dependency wiring. Flutter keeps
    // only its platform-specific native text/link seam below; Android/iOS deliberately
    // own a separately pinned static FreeType/HarfBuzz product.
    const client_dependency = b.dependency("howl_client", .{
        .target = target,
        .optimize = optimize,
    });
    const client = client_dependency.module("howl_client");
    const local = client_dependency.module("howl_local");

    const server_client = b.dependency("server_client", .{
        .target = target,
        .optimize = optimize,
    }).module("server_client");

    const vt = b.dependency("howl_vt", .{
        .target = target,
        .optimize = optimize,
    }).module("howl_vt");

    const text = localModule(b, target, optimize, repo, "howl-text/src/text.zig");
    text.link_libc = true;
    text.addImport("native_c", native_c);

    const limits = localModule(b, target, optimize, repo, "howl-render/src/limits.zig");
    const source = localModule(b, target, optimize, repo, "howl-render/src/source.zig");
    const renderer = localModule(b, target, optimize, repo, "howl-render/src/renderer.zig");
    renderer.addImport("limits", limits);
    renderer.addImport("source", source);
    renderer.addImport("howl_text", text);

    const terminal = localModule(b, target, optimize, repo, "howl-render/src/terminal.zig");
    terminal.addImport("renderer", renderer);
    terminal.addImport("source", source);
    terminal.addImport("howl_client", client);
    terminal.addImport("howl_vt", vt);

    const root = b.createModule(.{
        .root_source_file = b.path("host.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    root.addImport("howl_client", client);
    root.addImport("howl_local", local);
    root.addImport("server_client", server_client);
    root.addImport("howl_text", text);
    root.addImport("terminal", terminal);
    root.addImport("limits", limits);

    const object = b.addObject(.{
        .name = "howl_flutter_native_host",
        .root_module = root,
        .use_llvm = true,
        .use_lld = false,
    });
    b.getInstallStep().dependOn(
        &b.addInstallFile(object.getEmittedBin(), "howl_flutter_native_host.o").step,
    );

    const tests = b.addTest(.{
        .name = "howl_flutter_native_host_tests",
        .root_module = root,
        .use_llvm = false,
        .use_lld = false,
    });
    if (ndk == null and apple_sdk == null) {
        tests.root_module.linkSystemLibrary("freetype", .{});
        tests.root_module.linkSystemLibrary("harfbuzz", .{});
    }
    const test_step = b.step("test", "Run native host presentation-lattice proofs");
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

fn localModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    repo: []const u8,
    relative: []const u8,
) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = .{ .cwd_relative = b.pathJoin(&.{ repo, relative }) },
        .target = target,
        .optimize = optimize,
    });
}
