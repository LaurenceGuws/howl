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

    const pty = localModule(b, target, optimize, repo, "howl-pty/src/howl_pty.zig");
    const vt = localModule(b, target, optimize, repo, "howl-vt/src/howl_vt.zig");
    const session = localModule(b, target, optimize, repo, "howl-session/src/session.zig");
    session.addImport("howl_pty", pty);
    session.addImport("howl_vt", vt);

    const client = localModule(b, target, optimize, repo, "howl-client/src/howl_client.zig");
    client.addImport("howl_session", session);

    const text_package = b.dependency("howl_text", .{});
    const text = b.createModule(.{
        .root_source_file = text_package.path("src/text.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    text.addImport("native_c", native_c);

    const validation = localModule(b, target, optimize, repo, "howl-render/src/canvas_validation.zig");
    const canvas = localModule(b, target, optimize, repo, "howl-render/src/canvas.zig");
    canvas.addImport("canvas_validation", validation);

    const terminal = localModule(b, target, optimize, repo, "howl-render/src/terminal_native.zig");
    terminal.addImport("howl_client", client);
    terminal.addImport("howl_text", text);
    terminal.addImport("canvas", canvas);

    const root = b.createModule(.{
        .root_source_file = b.path("host.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    root.addImport("howl_client", client);
    root.addImport("howl_session", session);
    root.addImport("howl_text", text);
    root.addImport("canvas", canvas);
    root.addImport("terminal", terminal);

    const object = b.addObject(.{
        .name = "howl_flutter_native_host",
        .root_module = root,
        .use_llvm = true,
        .use_lld = false,
    });
    b.getInstallStep().dependOn(
        &b.addInstallFile(object.getEmittedBin(), "howl_flutter_native_host.o").step,
    );
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
