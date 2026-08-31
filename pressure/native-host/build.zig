const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const ndk = b.option([]const u8, "ndk", "Android NDK root") orelse
        @panic("native host pressure requires -Dndk=/path/to/ndk");
    const deps = b.option([]const u8, "deps", "Private FreeType/HarfBuzz prefix") orelse
        @panic("native host pressure requires -Ddeps=/path/to/prefix");
    const ndk_include = b.pathJoin(&.{
        ndk,
        "toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include",
    });
    const ndk_arch_include = b.pathJoin(&.{ ndk_include, "aarch64-linux-android" });

    const translate = b.addTranslateC(.{
        .root_source_file = b.path("native.h"),
        .target = target,
        .optimize = optimize,
    });
    translate.addSystemIncludePath(b.path("ndk-overlay"));
    translate.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ deps, "include/freetype2" }) });
    translate.addIncludePath(.{ .cwd_relative = b.pathJoin(&.{ deps, "include" }) });
    translate.addSystemIncludePath(.{ .cwd_relative = ndk_include });
    translate.addSystemIncludePath(.{ .cwd_relative = ndk_arch_include });
    const native_c = translate.createModule();

    const pty = b.createModule(.{
        .root_source_file = b.path("../../howl-pty/src/howl_pty.zig"),
        .target = target,
        .optimize = optimize,
    });
    const vt = b.createModule(.{
        .root_source_file = b.path("../../howl-vt/src/howl_vt.zig"),
        .target = target,
        .optimize = optimize,
    });
    const session = b.createModule(.{
        .root_source_file = b.path("../../howl-session/src/session.zig"),
        .target = target,
        .optimize = optimize,
    });
    session.addImport("howl_pty", pty);
    session.addImport("howl_vt", vt);

    const client = b.createModule(.{
        .root_source_file = b.path("../../howl-client/src/howl_client.zig"),
        .target = target,
        .optimize = optimize,
    });
    client.addImport("howl_session", session);

    const text = b.createModule(.{
        .root_source_file = b.path("howl-text/src/text.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    text.addImport("native_c", native_c);

    const canvas_validation = b.createModule(.{
        .root_source_file = b.path("../../howl-render/src/canvas_validation.zig"),
        .target = target,
        .optimize = optimize,
    });
    const canvas = b.createModule(.{
        .root_source_file = b.path("../../howl-render/src/canvas.zig"),
        .target = target,
        .optimize = optimize,
    });
    canvas.addImport("canvas_validation", canvas_validation);

    const terminal = b.createModule(.{
        .root_source_file = b.path("../../howl-render/src/terminal_native.zig"),
        .target = target,
        .optimize = optimize,
    });
    terminal.addImport("howl_client", client);
    terminal.addImport("howl_text", text);
    terminal.addImport("canvas", canvas);

    const root = b.createModule(.{
        .root_source_file = b.path("bridge.zig"),
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
    const install = b.addInstallFile(object.getEmittedBin(), "howl_flutter_native_host.o");
    b.getInstallStep().dependOn(&install.step);
}
