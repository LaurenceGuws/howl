const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const native_c = b.createModule(.{
        .root_source_file = b.path("generated/native_c.zig"),
        .target = target,
        .optimize = optimize,
    });
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

    const howl_text = b.createModule(.{
        .root_source_file = b.path("howl-text/src/text.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    howl_text.addImport("native_c", native_c);

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
    terminal.addImport("howl_text", howl_text);
    terminal.addImport("canvas", canvas);

    const host_root = b.createModule(.{
        .root_source_file = b.path("../native-host/bridge.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    host_root.addImport("howl_client", client);
    host_root.addImport("howl_session", session);
    host_root.addImport("howl_text", howl_text);
    host_root.addImport("canvas", canvas);
    host_root.addImport("terminal", terminal);

    const canary_root = b.createModule(.{
        .root_source_file = b.path("canary.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = true,
    });
    canary_root.addImport("howl_client", client);
    canary_root.addImport("howl_text", howl_text);
    canary_root.addImport("canvas", canvas);
    canary_root.addImport("terminal", terminal);

    const host = b.addObject(.{
        .name = "howl_native_host_ios",
        .root_module = host_root,
        .use_llvm = true,
        .use_lld = false,
    });
    const canary = b.addObject(.{
        .name = "howl_native_canary_ios",
        .root_module = canary_root,
        .use_llvm = true,
        .use_lld = false,
    });
    b.getInstallStep().dependOn(&b.addInstallFile(host.getEmittedBin(), "howl_native_host_ios.o").step);
    b.getInstallStep().dependOn(&b.addInstallFile(canary.getEmittedBin(), "howl_native_canary_ios.o").step);
}
